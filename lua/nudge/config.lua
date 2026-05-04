local M = {}

M.defaults = {
  auth = {
    -- "api_key"   : direct Anthropic API (requires API key)
    -- "claude_cli": delegates to the `claude` CLI binary, which handles
    --               OAuth for Claude Code / Pro subscriptions automatically
    provider = "api_key",
    api_key = nil, -- falls back to ANTHROPIC_API_KEY env var when nil
  },
  model = "claude-opus-4-5",
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
    "When generating or modifying code, output ONLY the raw code.",
    "Do NOT wrap the output in markdown code fences (``` blocks).",
    "Do NOT add explanations, comments, or any text beyond the code itself.",
    "Preserve the indentation style of any code provided as context.",
  }, "\n"),
}

---@param opts table
---@return table
function M.resolve(opts)
  return vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
