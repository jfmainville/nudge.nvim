-- Guard against double-loading
if vim.g.loaded_nudge then
  return
end
vim.g.loaded_nudge = true

-- Expose :Nudge command as a convenience
vim.api.nvim_create_user_command("Nudge", function(opts)
  local nudge = require("nudge")
  if nudge._config and next(nudge._config) ~= nil then
    require("nudge.ui").open_prompt(nudge._config, false)
  else
    vim.notify("Nudge: call require('nudge').setup({}) first", vim.log.levels.WARN)
  end
end, { desc = "Open Nudge AI prompt" })
