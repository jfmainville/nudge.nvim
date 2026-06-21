local config_module = require("nudge.config")
local ui      = require("nudge.ui")
local chat    = require("nudge.chat")
local context = require("nudge.context")

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

	vim.keymap.set("n", M._config.keymaps.chat, function()
		chat.open(M._config)
	end, { desc = "Nudge: open chat" })

	vim.keymap.set("n", M._config.keymaps.add_context, function()
		context.open_picker()
	end, { desc = "Nudge: manage context files" })

	-- Visual mode ("x" = visual only, excludes select mode):
	-- Capture the range NOW while still in visual mode, then exit.
	vim.keymap.set("x", key, function()
		local sr = vim.fn.line("v")
		local er = vim.fn.line(".")
		if sr > er then
			sr, er = er, sr
		end
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
		ui.open_prompt(M._config, true, sr, er)
	end, { desc = "Nudge: AI inline prompt (visual)" })
end

return M
