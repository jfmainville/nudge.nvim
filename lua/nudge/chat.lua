local api        = require("nudge.api")
local typewriter = require("nudge.typewriter")

local M = {}

local NS = vim.api.nvim_create_namespace("nudge.chat")
local AUGROUP = vim.api.nvim_create_augroup("nudge_chat", { clear = true })

-- Persists across open/close within the Neovim session.
local state = {
	history = {},
	chat_buf = nil,
	input_buf = nil,
	chat_win = nil,
	input_win = nil,
	stream_job = nil,
	stream_start = nil, -- 0-indexed line where current stream content begins
}

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local function dimensions()
	local tw, th = vim.o.columns, vim.o.lines
	local w = math.max(60, math.floor(tw * 0.72))
	local chat_h = math.max(12, math.floor(th * 0.65))
	local input_h = 1
	-- visual rows consumed: (chat_h+2 border) + (input_h+2 border)
	local vis = chat_h + 2 + input_h + 2
	local start_row = math.max(0, math.floor((th - vis) / 2))
	return {
		w = w,
		chat_h = chat_h,
		input_h = input_h,
		chat_row = start_row,
		input_row = start_row + chat_h + 2, -- directly below chat border
		col = math.floor((tw - w) / 2),
	}
end

-- ---------------------------------------------------------------------------
-- Buffer utilities
-- ---------------------------------------------------------------------------

local function set_modifiable(v)
	if state.chat_buf and vim.api.nvim_buf_is_valid(state.chat_buf) then
		vim.bo[state.chat_buf].modifiable = v
	end
end

-- Append lines; return the 0-indexed position of the first new line.
local function buf_append(lines)
	local n = vim.api.nvim_buf_line_count(state.chat_buf)
	vim.api.nvim_buf_set_lines(state.chat_buf, n, n, false, lines)
	return n
end

local function hl_line(row, hl)
	vim.api.nvim_buf_set_extmark(state.chat_buf, NS, row, 0, {
		end_row = row + 1,
		hl_group = hl,
		hl_eol = true,
		priority = 200,
	})
end

-- Add a blank separator unless the buffer is brand-new empty or already ends with one.
local function maybe_blank()
	local n = vim.api.nvim_buf_line_count(state.chat_buf)
	local last = (vim.api.nvim_buf_get_lines(state.chat_buf, n - 1, n, false))[1] or ""
	if n == 1 and last == "" then
		return
	end
	if last ~= "" then
		vim.api.nvim_buf_set_lines(state.chat_buf, n, n, false, { "" })
	end
end

local function scroll_to_bottom()
	if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
		local n = vim.api.nvim_buf_line_count(state.chat_buf)
		pcall(vim.api.nvim_win_set_cursor, state.chat_win, { n, 0 })
	end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local HL = { user = "Title", assistant = "Function", sep = "Comment", err = "DiagnosticError" }

local function render_header(role, model)
	local label = role == "user" and "You" or (model or "Assistant")
	local h_row = buf_append({ label })
	hl_line(h_row, HL[role] or "Normal")
	local sep_row = buf_append({ string.rep("─", vim.fn.strdisplaywidth(label)) })
	hl_line(sep_row, HL.sep)
	buf_append({ "" })
end

-- Render a complete message (used when replaying history on re-open).
local function render_full_message(role, content, model)
	set_modifiable(true)
	maybe_blank()
	render_header(role, model)
	buf_append(vim.split(content, "\n", { plain = true }))
	set_modifiable(false)
	scroll_to_bottom()
end

-- Write the assistant header, return the 0-indexed content start line.
local function begin_stream(model)
	set_modifiable(true)
	maybe_blank()
	render_header("assistant", model)
	local start = vim.api.nvim_buf_line_count(state.chat_buf)
	set_modifiable(false)
	return start
end

-- Replace streaming content from stream_start to the end of the buffer.
local function update_stream(accumulated)
	if state.stream_start == nil then
		return
	end
	set_modifiable(true)
	vim.api.nvim_buf_set_lines(
		state.chat_buf,
		state.stream_start,
		-1,
		false,
		vim.split(accumulated, "\n", { plain = true })
	)
	set_modifiable(false)
	scroll_to_bottom()
end

-- ---------------------------------------------------------------------------
-- Close
-- ---------------------------------------------------------------------------

local function close()
	-- Clear autocmds first to prevent re-entrant WinClosed callbacks.
	vim.api.nvim_clear_autocmds({ group = AUGROUP })

	if state.stream_job then
		pcall(vim.fn.jobstop, state.stream_job)
		state.stream_job = nil
	end

	-- Nil state before closing so any stray callbacks are no-ops.
	local wins = { state.chat_win, state.input_win }
	state.chat_win = nil
	state.input_win = nil
	state.chat_buf = nil
	state.input_buf = nil
	state.stream_start = nil

	for _, w in ipairs(wins) do
		if w and vim.api.nvim_win_is_valid(w) then
			pcall(vim.api.nvim_win_close, w, true)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Submit
-- ---------------------------------------------------------------------------

local function submit(config)
	if state.stream_job then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
	local prompt = vim.trim(table.concat(lines, " "))
	if prompt == "" then
		return
	end

	vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

	-- Render user turn
	set_modifiable(true)
	maybe_blank()
	render_header("user", nil)
	buf_append(vim.split(prompt, "\n", { plain = true }))
	set_modifiable(false)
	scroll_to_bottom()

	table.insert(state.history, { role = "user", content = prompt })

	state.stream_start = begin_stream(config.model)

	local typewriter_instance = typewriter.new(function(text)
		update_stream(text)
	end, {
		chars_per_tick = config.ui.typewriter_chars_per_tick,
		interval       = config.ui.typewriter_interval,
	})

	-- Use the chat-specific system prompt
	local chat_cfg = vim.tbl_extend("force", config, {
		system_prompt = config.chat_system_prompt,
	})

	state.stream_job = api.stream(chat_cfg, state.history, function(token)
		typewriter_instance:push(token)
	end, function()
		state.stream_job = nil
		typewriter_instance:finish(function(full_text)
			state.stream_start = nil
			table.insert(state.history, { role = "assistant", content = full_text })
		end)
	end, function(err)
		state.stream_job = nil
		state.stream_start = nil
		typewriter_instance:abort()
		set_modifiable(true)
		local err_row = buf_append({ "", "⚠  " .. err })
		hl_line(err_row + 1, HL.err)
		set_modifiable(false)
		scroll_to_bottom()
	end)
end

-- ---------------------------------------------------------------------------
-- Open
-- ---------------------------------------------------------------------------

function M.open(config)
	-- Already open: just focus the input.
	if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
		if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
			vim.api.nvim_set_current_win(state.input_win)
			vim.cmd("startinsert")
		end
		return
	end

	local d = dimensions()

	-- Chat display buffer (read-only)
	state.chat_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.chat_buf].buftype = "nofile"
	vim.bo[state.chat_buf].bufhidden = "wipe"
	vim.bo[state.chat_buf].buflisted = false
	vim.bo[state.chat_buf].swapfile = false
	vim.bo[state.chat_buf].modifiable = false

	-- Input buffer
	state.input_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.input_buf].buftype = "nofile"
	vim.bo[state.input_buf].bufhidden = "wipe"
	vim.bo[state.input_buf].buflisted = false
	vim.bo[state.input_buf].swapfile = false

	-- Chat window (not focused)
	state.chat_win = vim.api.nvim_open_win(state.chat_buf, false, {
		relative = "editor",
		row = d.chat_row,
		col = d.col,
		width = d.w,
		height = d.chat_h,
		border = "rounded",
		title = (" Nudge Chat · %s "):format(config.model),
		title_pos = "center",
		style = "minimal",
		noautocmd = true,
	})
	vim.wo[state.chat_win].wrap = true
	vim.wo[state.chat_win].linebreak = true
	vim.wo[state.chat_win].cursorline = false
	vim.api.nvim_win_call(state.chat_win, function()
		vim.bo.filetype = "markdown"
		vim.wo.conceallevel = 2
	end)

	-- Input window (focused)
	state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
		relative = "editor",
		row = d.input_row,
		col = d.col,
		width = d.w,
		height = d.input_h,
		border = "rounded",
		title = " Prompt (Enter to send · Esc to close) ",
		title_pos = "center",
		style = "minimal",
		noautocmd = true,
	})

	vim.cmd("startinsert")

	-- Replay history into the fresh buffer.
	for _, msg in ipairs(state.history) do
		render_full_message(msg.role, msg.content, config.model)
	end

	-- Input keymaps
	local function imap(mode, lhs, rhs)
		vim.keymap.set(mode, lhs, rhs, { buffer = state.input_buf, noremap = true, silent = true })
	end
	imap("i", "<CR>", function()
		submit(config)
	end)
	imap("i", "<Esc>", close)
	imap("n", "<Esc>", close)
	imap("n", "q", close)
	local function focus_chat_win()
		if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
			vim.api.nvim_set_current_win(state.chat_win)
		end
	end
	imap("i", "<C-j>", focus_chat_win)
	imap("n", "<C-j>", focus_chat_win)
	imap("i", "<C-k>", focus_chat_win)
	imap("n", "<C-k>", focus_chat_win)

	-- Chat display keymaps
	local function cmap(lhs, rhs)
		vim.keymap.set("n", lhs, rhs, { buffer = state.chat_buf, noremap = true, silent = true })
	end
	cmap("q", close)
	cmap("<Esc>", close)
	local function focus_input_win()
		if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
			vim.api.nvim_set_current_win(state.input_win)
			vim.cmd("startinsert")
		end
	end
	cmap("i", focus_input_win)
	cmap("<C-j>", focus_input_win)
	cmap("<C-k>", focus_input_win)

	-- Clean up state when either window is closed externally (e.g. :q).
	vim.api.nvim_create_autocmd("WinClosed", {
		group = AUGROUP,
		callback = function(args)
			local closed = tonumber(args.match)
			if closed == state.chat_win or closed == state.input_win then
				vim.schedule(close)
			end
		end,
	})
end

-- ---------------------------------------------------------------------------
-- Clear history (keeps the window open if it is open)
-- ---------------------------------------------------------------------------

function M.clear()
	state.history = {}
	if state.chat_buf and vim.api.nvim_buf_is_valid(state.chat_buf) then
		set_modifiable(true)
		vim.api.nvim_buf_set_lines(state.chat_buf, 0, -1, false, { "" })
		set_modifiable(false)
	end
end

return M
