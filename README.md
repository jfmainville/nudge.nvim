# nudge.nvim

An inline AI coding assistant for Neovim powered by Claude. Press `<leader>aa` to open a floating prompt, type your instruction, and watch the generated code appear directly in your buffer — no side panels, no context switching.

## Features

- **Inline prompt** — a small floating window appears at the centre of the screen; type and press `<Enter>`
- **Streaming preview** — generated tokens appear as virtual-text below the cursor while the model is still writing
- **Visual-mode replacement** — select code, press `<leader>aa`, describe what to change; the selection is replaced in-place
- **Normal-mode insertion** — with no selection, new code is inserted below the cursor
- **Live spinner** — a progress indicator shows while the request is in flight
- **Two auth providers**
  - `api_key` — direct Anthropic HTTPS API (pay-per-token)
  - `claude_cli` — delegates to the `claude` CLI binary which handles OAuth for Claude Code / Pro subscriptions automatically

---

## Requirements

- Neovim ≥ 0.9
- `curl` (for the `api_key` provider)
- **OR** the [Claude Code CLI](https://code.claude.com) logged in via `claude auth login` (for the `claude_cli` provider)

---

## Installation

### lazy.nvim

```lua
{
  "you/nudge.nvim",           -- replace with your actual repo path
  config = function()
    require("nudge").setup({
      auth = {
        provider = "api_key",
        api_key = "sk-ant-...", -- or omit and export ANTHROPIC_API_KEY
      },
    })
  end,
}
```

### packer.nvim

```lua
use {
  "you/nudge.nvim",
  config = function()
    require("nudge").setup()
  end,
}
```

---

## Configuration

Call `require("nudge").setup(opts)` with any of the options below. All fields are optional — the table shows defaults.

```lua
require("nudge").setup({

  -- Authentication --------------------------------------------------------
  auth = {
    -- "api_key"   : calls the Anthropic API directly with curl
    -- "claude_cli": runs `claude -p "…"` which uses your logged-in session
    provider = "api_key",

    -- API key for the "api_key" provider.
    -- When nil, falls back to the ANTHROPIC_API_KEY environment variable.
    api_key = nil,
  },

  -- Model to use (passed verbatim to whichever provider is active) --------
  model = "claude-opus-4-5",

  -- Maximum tokens in the model response ---------------------------------
  max_tokens = 8192,

  -- Keymaps ---------------------------------------------------------------
  keymaps = {
    prompt = "<leader>aa",  -- open the prompt (normal + visual)
    submit = "<CR>",        -- confirm prompt in the input window
    close  = "<Esc>",       -- dismiss the input window
  },

  -- UI tweaks -------------------------------------------------------------
  ui = {
    border          = "rounded",   -- any nvim_open_win border style
    title           = " Nudge ",
    title_pos       = "center",
    width           = 0.6,         -- fraction of editor columns
    spinner_frames  = { "⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏" },
    spinner_interval = 80,         -- ms between spinner frames
  },

  -- System prompt sent on every request ----------------------------------
  -- Override to add project-specific instructions.
  system_prompt = [[
You are an expert coding assistant embedded inside a code editor.
When generating or modifying code, output ONLY the raw code.
Do NOT wrap the output in markdown code fences (``` blocks).
Do NOT add explanations, comments, or any text beyond the code itself.
Preserve the indentation style of any code provided as context.
  ]],
})
```

---

## Auth providers in detail

### `api_key` (default)

Uses `curl` to call `https://api.anthropic.com/v1/messages` with SSE streaming. Requires either:

- `auth.api_key = "sk-ant-..."` in the config, **or**
- `export ANTHROPIC_API_KEY=sk-ant-...` in your shell environment.

Billed against your [Anthropic API](https://console.anthropic.com) account.

### `claude_cli` (OAuth / Pro subscription)

Delegates to the [`claude` CLI](https://code.claude.com) binary:

```bash
claude --print "<your prompt>" --output-format text --model <model>
```

Authentication is handled entirely by the CLI. If you have logged in with:

```bash
claude auth login
```

…your active subscription (Claude Code subscription, API credits, etc.) is used automatically. No API key is needed in the plugin config.

> **Note:** The `claude_cli` provider does not stream tokens — it shows a spinner while the request runs and inserts the full response when done.

---

## Usage

| Mode   | Keys          | Behaviour                                                  |
|--------|---------------|------------------------------------------------------------|
| Normal | `<leader>aa`  | Open prompt → insert generated code below the cursor       |
| Visual | `<leader>aa`  | Open prompt → replace selected lines with generated code   |
| Input  | `<Enter>`     | Submit the prompt                                          |
| Input  | `<Esc>`       | Cancel                                                     |

A `:Nudge` command is also registered after `setup()`.

### Examples

**Generate a function**

Place your cursor where you want the function, press `<leader>aa`, type:

```
write a Go function that reads a JSON file and returns a map[string]any
```

Press `<Enter>`. The function appears below the cursor.

**Refactor selected code**

Select a block of code with `V` (linewise visual), press `<leader>aa`, type:

```
convert to use async/await and add proper error handling
```

Press `<Enter>`. The selection is replaced.

---

## Running tests

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim). Install it, then:

```bash
make test
```

Or run directly:

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/spec {minimal_init = 'tests/minimal_init.lua'}"
```

---

## Contributing

1. Keep modules focused — `config.lua`, `api.lua`, `ui.lua` each own one concern.
2. Run `make lint` and `make test` before opening a PR.
3. No external Lua runtime dependencies beyond `plenary` for tests.
