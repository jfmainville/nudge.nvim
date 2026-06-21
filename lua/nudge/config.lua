local M = {}

M.defaults = {
	auth = {
		-- "api_key"   : direct Anthropic API (requires API key)
		-- "claude_cli": delegates to the `claude` CLI binary, which handles
		--               OAuth for Claude Code / Pro subscriptions automatically
		provider = "api_key",
		api_key = nil, -- falls back to ANTHROPIC_API_KEY env var when nil
	},
	model = "claude-sonnet-4-6",
	max_tokens = 8192,
	keymaps = {
		prompt      = "<leader>aa",
		chat        = "<leader>ac",
		add_context = "<leader>af",
		submit      = "<CR>",
		close       = "<Esc>",
	},
	ui = {
		border = "rounded",
		title = " Nudge ",
		title_pos = "center",
		width = 0.6,
		spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
		spinner_interval = 80,
	},
	chat_system_prompt = table.concat({
		"You are a helpful coding assistant integrated into a code editor.",
		"Answer questions clearly and concisely.",
		"You may use markdown formatting in your responses, including code blocks.",
		"Keep your answers focused and practical.",
	}, " "),
	system_prompt = table.concat({
		"You are an expert coding assistant embedded inside a code editor.",
		"Do NOT wrap output in markdown code fences (``` blocks).",
		"Do NOT add explanations, comments, or any text beyond the code itself.",
		"Follow the output rule specified in each request exactly.",
		"If the question is unclear, do NOT list questions, make a reasonable attempt.",
	}, "\n"),
}

---@param opts table
---@return table
function M.resolve(opts)
	return vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
