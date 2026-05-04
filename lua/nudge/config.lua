local M = {}

M.defaults = {
	auth = {
		-- "api_key"   : direct Anthropic API (requires API key)
		-- "claude_cli": delegates to the `claude` CLI binary, which handles
		--               OAuth for Claude Code / Pro subscriptions automatically
		provider = "api_key",
		api_key = nil, -- falls back to ANTHROPIC_API_KEY env var when nil
	},
	model = "claude-haiku-4-5",
	max_tokens = 8192,
	keymaps = {
		prompt = "<leader>aa",
		submit = "<CR>",
		close = "<Esc>",
	},
	ui = {
		border = "rounded",
		title = " Nudge ",
		title_pos = "center",
		width = 0.6,
		spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
		spinner_interval = 80,
	},
	system_prompt = table.concat({
		"You are an expert coding assistant embedded inside a code editor.",
		"CRITICAL OUTPUT RULE: output ONLY the lines that will be inserted or will replace the selection.",
		"NEVER output the surrounding file, the unchanged lines, or the full file with edits applied.",
		"Do NOT wrap output in markdown code fences (``` blocks).",
		"Do NOT add explanations, comments, or any text beyond the code itself.",
		"Start your output at column 0, no leading indentation on the first line.",
		"Preserve relative indentation within the block (e.g. function bodies stay indented relative to their definition).",
		"The editor will apply the correct base indentation automatically.",
		"If the question is unclear, do NOT list questions, make a reasonable attempt.",
	}, "\n"),
}

---@param opts table
---@return table
function M.resolve(opts)
	return vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
