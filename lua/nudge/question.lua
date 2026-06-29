local api        = require("nudge.api")
local typewriter = require("nudge.typewriter")

local M = {}

local NS = vim.api.nvim_create_namespace("nudge.question")
local _count = 0

-- ---------------------------------------------------------------------------
-- Question detection
-- ---------------------------------------------------------------------------

local QUESTION_STARTERS = {
	"what", "how", "why", "when", "where", "who", "which",
	"can", "could", "does", "do", "is", "are", "will", "would", "should",
	"explain", "tell", "describe", "show", "find", "list",
}

function M.is_question(text)
	local t = vim.trim(text)
	if t:sub(-1) == "?" then return true end
	local first = t:lower():match("^(%a+)")
	if first then
		for _, w in ipairs(QUESTION_STARTERS) do
			if first == w then return true end
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local function dimensions()
	local tw, th  = vim.o.columns, vim.o.lines
	local w       = math.max(60, math.floor(tw * 0.72))
	local chat_h  = math.max(12, math.floor(th * 0.65))
	local input_h = 1
	local vis     = chat_h + 2 + input_h + 2
	local sr      = math.max(0, math.floor((th - vis) / 2))
	return {
		w         = w,
		chat_h    = chat_h,
		input_h   = input_h,
		chat_row  = sr,
		input_row = sr + chat_h + 2,
		col       = math.floor((tw - w) / 2),
	}
end

-- ---------------------------------------------------------------------------
-- Buffer / render helpers
-- ---------------------------------------------------------------------------

local HL = { user = "Title", assistant = "Function", sep = "Comment", err = "DiagnosticError" }

local function set_mod(buf, v)
	if buf and vim.api.nvim_buf_is_valid(buf) then
		vim.bo[buf].modifiable = v
	end
end

local function buf_append(buf, lines)
	local n = vim.api.nvim_buf_line_count(buf)
	vim.api.nvim_buf_set_lines(buf, n, n, false, lines)
	return n
end

local function hl_line(buf, row, hl)
	vim.api.nvim_buf_set_extmark(buf, NS, row, 0, {
		end_row  = row + 1,
		hl_group = hl,
		hl_eol   = true,
		priority = 200,
	})
end

local function maybe_blank(buf)
	local n    = vim.api.nvim_buf_line_count(buf)
	local last = (vim.api.nvim_buf_get_lines(buf, n - 1, n, false))[1] or ""
	if n == 1 and last == "" then return end
	if last ~= "" then
		vim.api.nvim_buf_set_lines(buf, n, n, false, { "" })
	end
end

local function scroll_bot(win, buf)
	if win and vim.api.nvim_win_is_valid(win) then
		local n = vim.api.nvim_buf_line_count(buf)
		pcall(vim.api.nvim_win_set_cursor, win, { n, 0 })
	end
end

local function render_header(buf, role, model)
	local label = role == "user" and "You" or (model or "Assistant")
	local h = buf_append(buf, { label })
	hl_line(buf, h, HL[role] or "Normal")
	local s = buf_append(buf, { string.rep("─", vim.fn.strdisplaywidth(label)) })
	hl_line(buf, s, HL.sep)
	buf_append(buf, { "" })
end

-- Build the initial user message that includes file / selection context.
local function build_initial_content(question_text, context, filetype, file_ctx, context_files)
	local parts = {}
	local ft    = filetype or "text"

	if context_files and #context_files > 0 then
		for _, cf in ipairs(context_files) do
			table.insert(parts, ("Context file: %s  (filetype: %s)"):format(cf.path, cf.filetype))
			table.insert(parts, cf.content)
			table.insert(parts, "---")
		end
	end

	if file_ctx and file_ctx.content ~= "" then
		local label = (file_ctx.name ~= "" and file_ctx.name) or "[No Name]"
		table.insert(parts, ("File: %s  (filetype: %s)"):format(label, ft))
		table.insert(parts, file_ctx.content)
		table.insert(parts, "---")
	end

	if context and context ~= "" then
		table.insert(parts, "Selected code:")
		table.insert(parts, context)
		table.insert(parts, "---")
	end

	table.insert(parts, question_text)
	return table.concat(parts, "\n")
end

-- ---------------------------------------------------------------------------
-- Open
-- ---------------------------------------------------------------------------

---@param config          table       Resolved nudge config
---@param initial_question string     The question to kick off the session
---@param context         string|nil  Visual selection text (may be nil/empty)
---@param filetype        string|nil  Buffer filetype
---@param file_ctx        table|nil   { name, content, cursor_row, sel_sr, sel_er, is_file_edit }
function M.open(config, initial_question, context, filetype, file_ctx, context_files)
	_count = _count + 1
	local AUGROUP = vim.api.nvim_create_augroup("nudge_question_" .. _count, { clear = true })

	local state = {
		chat_buf     = nil,
		input_buf    = nil,
		chat_win     = nil,
		input_win    = nil,
		stream_job   = nil,
		stream_start = nil,
		history      = {},
	}

	local d = dimensions()

	-- Chat display buffer (read-only)
	state.chat_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.chat_buf].buftype    = "nofile"
	vim.bo[state.chat_buf].bufhidden  = "wipe"
	vim.bo[state.chat_buf].buflisted  = false
	vim.bo[state.chat_buf].swapfile   = false
	vim.bo[state.chat_buf].modifiable = false

	-- Input buffer
	state.input_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.input_buf].buftype   = "nofile"
	vim.bo[state.input_buf].bufhidden = "wipe"
	vim.bo[state.input_buf].buflisted = false
	vim.bo[state.input_buf].swapfile  = false

	-- Chat window
	state.chat_win = vim.api.nvim_open_win(state.chat_buf, false, {
		relative  = "editor",
		row       = d.chat_row,
		col       = d.col,
		width     = d.w,
		height    = d.chat_h,
		border    = "rounded",
		title     = (" Nudge · %s "):format(config.model),
		title_pos = "center",
		style     = "minimal",
		noautocmd = true,
	})
	vim.wo[state.chat_win].wrap      = true
	vim.wo[state.chat_win].linebreak = true
	vim.wo[state.chat_win].cursorline = false
	vim.api.nvim_win_call(state.chat_win, function()
		vim.bo.filetype   = "markdown"
		vim.wo.conceallevel = 2
	end)

	-- Input window (starts focused)
	state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
		relative  = "editor",
		row       = d.input_row,
		col       = d.col,
		width     = d.w,
		height    = d.input_h,
		border    = "rounded",
		title     = " Follow-up (Enter to send · Esc to close) ",
		title_pos = "center",
		style     = "minimal",
		noautocmd = true,
	})

	-- -------------------------------------------------------------------------
	-- Close
	-- -------------------------------------------------------------------------

	local function close()
		vim.api.nvim_clear_autocmds({ group = AUGROUP })

		if state.stream_job then
			pcall(vim.fn.jobstop, state.stream_job)
			state.stream_job = nil
		end

		local wins = { state.chat_win, state.input_win }
		state.chat_win    = nil
		state.input_win   = nil
		state.chat_buf    = nil
		state.input_buf   = nil
		state.stream_start = nil

		for _, w in ipairs(wins) do
			if w and vim.api.nvim_win_is_valid(w) then
				pcall(vim.api.nvim_win_close, w, true)
			end
		end
	end

	-- -------------------------------------------------------------------------
	-- Streaming helpers
	-- -------------------------------------------------------------------------

	local function update_stream(accumulated)
		if state.stream_start == nil then return end
		set_mod(state.chat_buf, true)
		vim.api.nvim_buf_set_lines(
			state.chat_buf, state.stream_start, -1, false,
			vim.split(accumulated, "\n", { plain = true })
		)
		set_mod(state.chat_buf, false)
		scroll_bot(state.chat_win, state.chat_buf)
	end

	local function begin_stream()
		set_mod(state.chat_buf, true)
		maybe_blank(state.chat_buf)
		render_header(state.chat_buf, "assistant", config.model)
		local start = vim.api.nvim_buf_line_count(state.chat_buf)
		set_mod(state.chat_buf, false)
		return start
	end

	-- -------------------------------------------------------------------------
	-- Send
	-- display_text : what to render in the chat pane as the "You" turn
	-- api_messages : full history array (already includes the new user message)
	-- -------------------------------------------------------------------------

	local function send(display_text, api_messages)
		if state.stream_job then return end

		set_mod(state.chat_buf, true)
		maybe_blank(state.chat_buf)
		render_header(state.chat_buf, "user", nil)
		buf_append(state.chat_buf, vim.split(display_text, "\n", { plain = true }))
		set_mod(state.chat_buf, false)
		scroll_bot(state.chat_win, state.chat_buf)

		state.stream_start = begin_stream()

		local typewriter_instance = typewriter.new(function(text)
			update_stream(text)
		end, {
			chars_per_tick = config.ui.typewriter_chars_per_tick,
			interval       = config.ui.typewriter_interval,
		})

		local q_cfg = vim.tbl_extend("force", config, {
			system_prompt = config.chat_system_prompt,
		})

		state.stream_job = api.stream(
			q_cfg,
			api_messages,
			function(token)
				typewriter_instance:push(token)
			end,
			function()
				state.stream_job = nil
				typewriter_instance:finish(function(full_text)
					state.stream_start = nil
					table.insert(state.history, { role = "assistant", content = full_text })
				end)
			end,
			function(err)
				state.stream_job   = nil
				state.stream_start = nil
				typewriter_instance:abort()
				set_mod(state.chat_buf, true)
				local err_row = buf_append(state.chat_buf, { "", "⚠  " .. err })
				hl_line(state.chat_buf, err_row + 1, HL.err)
				set_mod(state.chat_buf, false)
				scroll_bot(state.chat_win, state.chat_buf)
			end
		)
	end

	-- -------------------------------------------------------------------------
	-- Submit follow-up
	-- -------------------------------------------------------------------------

	local function submit_followup()
		if state.stream_job then return end
		if not (state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf)) then return end

		local lines  = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
		local prompt = vim.trim(table.concat(lines, " "))
		if prompt == "" then return end
		vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

		table.insert(state.history, { role = "user", content = prompt })
		send(prompt, state.history)
	end

	-- -------------------------------------------------------------------------
	-- Keymaps
	-- -------------------------------------------------------------------------

	local function scroll_chat(motion)
		if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
			vim.api.nvim_win_call(state.chat_win, function()
				vim.cmd("normal! " .. motion)
			end)
		end
	end

	local function imap(mode, lhs, rhs)
		vim.keymap.set(mode, lhs, rhs, { buffer = state.input_buf, noremap = true, silent = true })
	end
	imap("i", config.keymaps.submit, submit_followup)
	imap("i", config.keymaps.close,  close)
	imap("n", config.keymaps.close,  close)
	imap("n", "q",                   close)
	imap("i", "<C-u>", function() scroll_chat("\x15") end)
	imap("n", "<C-u>", function() scroll_chat("\x15") end)
	imap("i", "<C-d>", function() scroll_chat("\x04") end)
	imap("n", "<C-d>", function() scroll_chat("\x04") end)
	local function focus_chat_win()
		if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
			vim.api.nvim_set_current_win(state.chat_win)
		end
	end
	imap("i", "<C-j>", focus_chat_win)
	imap("n", "<C-j>", focus_chat_win)
	imap("i", "<C-k>", focus_chat_win)
	imap("n", "<C-k>", focus_chat_win)

	local function cmap(lhs, rhs)
		vim.keymap.set("n", lhs, rhs, { buffer = state.chat_buf, noremap = true, silent = true })
	end
	cmap("q",     close)
	cmap("<Esc>", close)
	cmap("<C-u>", function() scroll_chat("\x15") end)
	cmap("<C-d>", function() scroll_chat("\x04") end)
	local function focus_input_win()
		if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
			vim.api.nvim_set_current_win(state.input_win)
			vim.cmd("startinsert")
		end
	end
	cmap("i",     focus_input_win)
	cmap("<C-j>", focus_input_win)
	cmap("<C-k>", focus_input_win)

	vim.api.nvim_create_autocmd("WinClosed", {
		group = AUGROUP,
		callback = function(args)
			local closed = tonumber(args.match)
			if closed == state.chat_win or closed == state.input_win then
				vim.schedule(close)
			end
		end,
	})

	-- -------------------------------------------------------------------------
	-- Kick off the initial question
	-- -------------------------------------------------------------------------

	local initial_content = build_initial_content(initial_question, context, filetype, file_ctx, context_files)
	table.insert(state.history, { role = "user", content = initial_content })

	vim.cmd("startinsert")
	send(initial_question, state.history)
end

return M
