local api = require("nudge.api")

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

local function get_visual_selection(buf)
  local s = vim.fn.getpos("'<")
  local e = vim.fn.getpos("'>")
  local sr, sc = s[2], s[3]
  local er, ec = e[2], e[3]

  local lines = vim.api.nvim_buf_get_lines(buf, sr - 1, er, false)
  local text = table.concat(lines, "\n")
  return text, sr, sc, er, ec
end

-- ---------------------------------------------------------------------------
-- Apply generated text to the buffer
-- ---------------------------------------------------------------------------

local function split_lines(text)
  -- Strip a single trailing newline that models commonly append
  text = text:gsub("\n$", "")
  return vim.split(text, "\n", { plain = true })
end

local function apply_result(buf, text, is_visual, sel_sr, sel_er, cursor_row)
  local lines = split_lines(text)
  if is_visual then
    -- Replace the selected lines wholesale (line-level replacement)
    vim.api.nvim_buf_set_lines(buf, sel_sr - 1, sel_er, false, lines)
    -- Restore cursor to start of replaced region
    vim.api.nvim_win_set_cursor(0, { sel_sr, 0 })
  else
    -- Insert below the cursor line
    vim.api.nvim_buf_set_lines(buf, cursor_row, cursor_row, false, lines)
    vim.api.nvim_win_set_cursor(0, { cursor_row + 1, 0 })
  end
end

-- ---------------------------------------------------------------------------
-- Floating prompt window
-- ---------------------------------------------------------------------------

local function open_input_win(config)
  local total_w = vim.o.columns
  local total_h = vim.o.lines
  local width = math.max(40, math.floor(total_w * config.ui.width))
  local row = math.floor((total_h - 3) / 2)
  local col = math.floor((total_w - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buflisted = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = 1,
    row = row,
    col = col,
    style = "minimal",
    border = config.ui.border,
    title = config.ui.title,
    title_pos = config.ui.title_pos,
    noautocmd = true,
  })

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

---@param config table  Resolved nudge config
---@param is_visual boolean  Whether called from visual mode
function M.open_prompt(config, is_visual)
  local target_buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor[1]
  local filetype = vim.bo[target_buf].filetype or ""

  local context, sel_sr, sel_er
  if is_visual then
    local text, sr, _sc, er = get_visual_selection(target_buf)
    context, sel_sr, sel_er = text, sr, er
  end

  local input_buf, input_win = open_input_win(config)

  local function on_submit()
    local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
    local prompt = vim.trim(table.concat(lines, " "))
    close_input(input_buf, input_win)

    if prompt == "" then
      return
    end

    -- Return to the target buffer/window
    local target_win = vim.fn.bufwinid(target_buf)
    if target_win ~= -1 then
      vim.api.nvim_set_current_win(target_win)
    end

    local messages = api.build_messages(prompt, context or "", filetype)
    local spinner = Spinner.new(
      target_buf, cursor_row,
      config.ui.spinner_frames, config.ui.spinner_interval
    )
    local preview_id = nil
    local accumulated = ""

    api.stream(
      config,
      messages,
      function(token)
        accumulated = accumulated .. token
        preview_id = set_preview(target_buf, cursor_row, accumulated, preview_id)
      end,
      function()
        spinner:stop()
        clear_mark(target_buf, preview_id)
        apply_result(target_buf, accumulated, is_visual, sel_sr, sel_er, cursor_row)
      end,
      function(err)
        spinner:stop()
        clear_mark(target_buf, preview_id)
        vim.notify("Nudge: " .. err, vim.log.levels.ERROR)
      end
    )
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
