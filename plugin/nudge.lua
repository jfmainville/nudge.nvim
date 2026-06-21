-- Guard against double-loading
if vim.g.loaded_nudge then
	return
end
vim.g.loaded_nudge = true

local function assert_setup()
	local nudge = require("nudge")
	if not nudge._config or next(nudge._config) == nil then
		vim.notify("Nudge: call require('nudge').setup({}) first", vim.log.levels.WARN)
		return nil
	end
	return nudge._config
end

vim.api.nvim_create_user_command("Nudge", function()
	local cfg = assert_setup()
	if cfg then
		require("nudge.ui").open_prompt(cfg, false)
	end
end, { desc = "Open Nudge inline AI prompt" })

vim.api.nvim_create_user_command("NudgeChat", function()
	local cfg = assert_setup()
	if cfg then
		require("nudge.chat").open(cfg)
	end
end, { desc = "Open Nudge chat window" })

vim.api.nvim_create_user_command("NudgeChatClear", function()
	require("nudge.chat").clear()
end, { desc = "Clear Nudge chat history" })

vim.api.nvim_create_user_command("NudgeContext", function()
	if assert_setup() then
		require("nudge.context").open_picker()
	end
end, { desc = "Manage Nudge context files (telescope)" })

vim.api.nvim_create_user_command("NudgeContextClear", function()
	require("nudge.context").clear()
	vim.notify("Nudge: context cleared", vim.log.levels.INFO)
end, { desc = "Clear all Nudge context files" })
