local config_module = require("nudge.config")
local ui = require("nudge.ui")

local M = {}

---@type table
M._config = {}

---@param opts table?
function M.setup(opts)
  M._config = config_module.resolve(opts)
  M._register_keymaps()
end

function M._register_keymaps()
  local key = M._config.keymaps.prompt

  vim.keymap.set("n", key, function()
    ui.open_prompt(M._config, false)
  end, { desc = "Nudge: AI inline prompt" })

  -- Visual mode: exit visual first so '< '> marks are set, then open prompt
  vim.keymap.set("v", key, function()
    -- <Esc> commits the visual selection marks before we read them
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
      "nx", false
    )
    ui.open_prompt(M._config, true)
  end, { desc = "Nudge: AI inline prompt (visual)" })
end

return M
