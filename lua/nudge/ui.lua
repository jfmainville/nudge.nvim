local api        = require("nudge.api")
local ctx_module = require("nudge.context")
local question   = require("nudge.question")
local typewriter = require("nudge.typewriter")

local M = {}

local NS = vim.api.nvim_create_namespace("nudge")

-- ---------------------------------------------------------------------------
-- Spinner
-- ---------------------------------------------------------------------------

local Spinner = {}
Spinner.__index = Spinner

function Spinner.new(buf, row, frames, interval)
	local self = setmetatable({
		buf = buf,
		row = row,
		frames = frames,
		interval = interval,
		frame = 1,
		mark_id = nil,
		timer = nil,
	}, Spinner)
	self:_place()
	self.timer = vim.fn.timer_start(interval, function()
		self:_tick()
	end, { ["repeat"] = -1 })
	return self
end

function Spinner:_place()
	local opts = {
		virt_text = { { self.frames[self.frame] .. " Generating…", "Comment" } },
		virt_text_pos = "eol",
	}
	if self.mark_id then
		opts.id = self.mark_id
	end
	self.mark_id = vim.api.nvim_buf_set_extmark(self.buf, NS, self.row - 1, 0, opts)
end

function Spinner:_tick()
	if not vim.api.nvim_buf_is_valid(self.buf) then
		self:stop()
		return
	end
	self.frame = (self.frame % #self.frames) + 1
	self:_place()
end

function Spinner:stop()
	if self.timer then
		vim.fn.timer_stop(self.timer)
		self.timer = nil
	end
	if self.mark_id and vim.api.nvim_buf_is_valid(self.buf) then
		pcall(vim.api.nvim_buf_del_extmark, self.buf, NS, self.mark_id)
		self.mark_id = nil
	end
end

-- ---------------------------------------------------------------------------
-- Preview (streaming virtual lines)
-- ---------------------------------------------------------------------------

local function set_preview(buf, row, text, mark_id)
	local lines = vim.split(text, "\n", { plain = true })
	local virt_lines = vim.tbl_map(function(l)
		return { { l, "DiffAdd" } }
	end, lines)

	local opts = { virt_lines = virt_lines }
	if mark_id then
		opts.id = mark_id
		vim.api.nvim_buf_set_extmark(buf, NS, row - 1, 0, opts)
		return mark_id
	end
	return vim.api.nvim_buf_set_extmark(buf, NS, row - 1, 0, opts)
end

local function clear_mark(buf, mark_id)
	if mark_id then
		pcall(vim.api.nvim_buf_del_extmark, buf, NS, mark_id)
	end
end

-- ---------------------------------------------------------------------------
-- Visual selection helpers
-- ---------------------------------------------------------------------------

local function get_visual_lines(buf, sr, er)
	local lines = vim.api.nvim_buf_get_lines(buf, sr - 1, er, false)
	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- Apply generated text to the buffer
-- ---------------------------------------------------------------------------

local function split_lines(text)
	text = text:gsub("\n$", "")
	return vim.split(text, "\n", { plain = true })
end

-- Return the leading whitespace of a buffer line (1-indexed row).
local function line_indent(buf, row)
	local line = (vim.api.nvim_buf_get_lines(buf, row - 1, row, false))[1] or ""
	return line:match("^(%s*)") or ""
end

-- Strip the common base indentation from all non-empty lines, then prefix
-- every line with target_indent.  Preserves relative indentation within
-- the block.
local function reindent(lines, target_indent)
	-- Find minimum indentation across non-empty lines
	local min_ind = math.huge
	for _, l in ipairs(lines) do
		if l ~= "" then
			min_ind = math.min(min_ind, #(l:match("^(%s*)")))
		end
	end
	if min_ind == math.huge then
		min_ind = 0
	end

	local out = {}
	for _, l in ipairs(lines) do
		if l == "" then
			table.insert(out, "")
		else
			table.insert(out, target_indent .. l:sub(min_ind + 1))
		end
	end
	return out
end

-- mode: "replace_buffer" | "replace_selection" | "insert"
local function apply_result(buf, text, mode, sel_sr, sel_er, cursor_row)
	local lines = split_lines(text)

	if mode == "replace_buffer" then
		local cur = vim.api.nvim_win_get_cursor(0)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		local new_row = math.min(cur[1], #lines)
		pcall(vim.api.nvim_win_set_cursor, 0, { new_row, cur[2] })
	elseif mode == "replace_selection" then
		local indent = line_indent(buf, sel_sr)
		lines = reindent(lines, indent)
		vim.api.nvim_buf_set_lines(buf, sel_sr - 1, sel_er, false, lines)
		vim.api.nvim_win_set_cursor(0, { sel_sr, #indent })
	else -- "insert"
		local indent = line_indent(buf, cursor_row)
		lines = reindent(lines, indent)
		vim.api.nvim_buf_set_lines(buf, cursor_row, cursor_row, false, lines)
		vim.api.nvim_win_set_cursor(0, { cursor_row + 1, #indent })
	end
end

-- ---------------------------------------------------------------------------
-- Floating prompt window
-- ---------------------------------------------------------------------------

local function open_input_win(config)
	local total_w = vim.o.columns
	local total_h = vim.o.lines
	local width  = math.max(40, math.floor(total_w * config.ui.width))
	local height = 4
	local row    = math.floor((total_h - (height + 2)) / 2)
	local col    = math.floor((total_w - width) / 2)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].buflisted = false

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = config.ui.border,
		title = config.ui.title,
		title_pos = config.ui.title_pos,
		noautocmd = true,
	})

	vim.wo[win].wrap      = true
	vim.wo[win].linebreak = true

	vim.cmd("startinsert")
	return buf, win
end

local function close_input(buf, win)
	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

-- ---------------------------------------------------------------------------
-- Public: open_prompt
-- ---------------------------------------------------------------------------

---@param config table     Resolved nudge config
---@param is_visual boolean Whether called from visual mode
---@param vis_sr number|nil Visual selection start row (1-indexed), set by keymap before Esc
---@param vis_er number|nil Visual selection end row (1-indexed)
function M.open_prompt(config, is_visual, vis_sr, vis_er)
	local target_buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_row = cursor[1]
	local filetype = vim.bo[target_buf].filetype or ""

	-- Full file context
	local raw_name = vim.api.nvim_buf_get_name(target_buf)
	local file_name = raw_name ~= "" and vim.fn.fnamemodify(raw_name, ":~:.") or ""
	local file_lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
	local file_content = table.concat(file_lines, "\n")

	local context, sel_sr, sel_er
	if is_visual and vis_sr and vis_er then
		sel_sr, sel_er = vis_sr, vis_er
		context = get_visual_lines(target_buf, sel_sr, sel_er)
	end

	local mode = is_visual and "replace_selection" or "replace_buffer"

	local file_ctx = {
		name = file_name,
		content = file_content,
		cursor_row = cursor_row,
		sel_sr = sel_sr,
		sel_er = sel_er,
		is_file_edit = not is_visual,
	}

	local input_buf, input_win = open_input_win(config)

	local function on_submit()
		local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
		local prompt = vim.trim(table.concat(lines, " "))
		close_input(input_buf, input_win)
		vim.cmd("stopinsert")

		if prompt == "" then
			return
		end

		local context_files = ctx_module.get_file_contents()

		if question.is_question(prompt) then
			question.open(config, prompt, context, filetype, file_ctx, context_files)
			return
		end

		-- Return to the target buffer/window
		local target_win = vim.fn.bufwinid(target_buf)
		if target_win ~= -1 then
			vim.api.nvim_set_current_win(target_win)
		end

		local messages = api.build_messages(prompt, context or "", filetype, file_ctx, context_files)
		local spinner = Spinner.new(target_buf, cursor_row, config.ui.spinner_frames, config.ui.spinner_interval)
		local preview_id = nil

		local typewriter_instance = typewriter.new(function(text)
			if mode ~= "replace_buffer" then
				preview_id = set_preview(target_buf, cursor_row, text, preview_id)
			end
		end, {
			chars_per_tick = config.ui.typewriter_chars_per_tick,
			interval       = config.ui.typewriter_interval,
		})

		api.stream(config, messages, function(token)
			typewriter_instance:push(token)
		end, function()
			spinner:stop()
			typewriter_instance:finish(function(full_text)
				clear_mark(target_buf, preview_id)
				apply_result(target_buf, full_text, mode, sel_sr, sel_er, cursor_row)
			end)
		end, function(err)
			spinner:stop()
			typewriter_instance:abort()
			clear_mark(target_buf, preview_id)
			vim.notify("Nudge: " .. err, vim.log.levels.ERROR)
		end)
	end

	local function on_cancel()
		close_input(input_buf, input_win)
	end

	local map_opts = { buffer = input_buf, noremap = true, silent = true }
	vim.keymap.set("i", config.keymaps.submit, on_submit, map_opts)
	vim.keymap.set("i", config.keymaps.close, on_cancel, map_opts)
	vim.keymap.set("n", config.keymaps.close, on_cancel, map_opts)

	-- Close if user moves focus away
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = input_buf,
		once = true,
		callback = on_cancel,
	})
end

return M
