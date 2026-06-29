# nudge.nvim

An inline AI coding assistant for Neovim powered by Claude. Press `<leader>aa` to open a floating prompt, type your instruction, and watch the generated code appear directly in your buffer, with no side panels and no context switching.

## Features

- **Inline prompt**: a small floating window appears at the centre of the screen; type and press `<Enter>`
- **Streaming preview**: generated tokens appear as virtual-text below the cursor while the model is still writing, revealed with a smooth typewriter animation
- **Visual-mode replacement**: select code, press `<leader>aa`, describe what to change; the selection is replaced in-place
- **Normal-mode insertion**: with no selection, new code is inserted below the cursor
- **Live spinner**: a progress indicator shows while the request is in flight
- **Chat mode**: a persistent two-pane window for multi-turn conversations with the model
- **File context**: attach additional files to every AI request via telescope so the model is aware of code outside the current buffer
- **Two auth providers**
  - `api_key`: direct Anthropic HTTPS API (pay-per-token)
  - `claude_cli`: delegates to the `claude` CLI binary which handles OAuth for Claude Code / Pro subscriptions automatically

---

## Requirements

- Neovim >= 0.11
- `curl` (for the `api_key` provider)
- **OR** the [Claude Code CLI](https://code.claude.com) logged in via `claude auth login` (for the `claude_cli` provider)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (for file context management)

---

## Installation

### lazy.nvim

```lua
{
  "jfmainville/nudge.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
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
  "jfmainville/nudge.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("nudge").setup()
  end,
}
```

---

## Configuration

Call `require("nudge").setup(opts)` with any of the options below. All fields are optional, the table shows defaults.

````lua
require("nudge").setup({

  -- Authentication --------------------------------------------------------
  auth = {
    -- "api_key"   : calls the Anthropic API directly with curl
    -- "claude_cli": runs `claude --print "..."` which uses your logged-in session
    provider = "api_key",

    -- API key for the "api_key" provider.
    -- When nil, falls back to the ANTHROPIC_API_KEY environment variable.
    api_key = nil,
  },

  -- Model to use (passed verbatim to whichever provider is active) --------
  model = "claude-sonnet-4-6",

  -- Maximum tokens in the model response ---------------------------------
  max_tokens = 8192,

  -- Keymaps ---------------------------------------------------------------
  keymaps = {
    prompt      = "<leader>aa",  -- open the inline prompt (normal + visual)
    chat        = "<leader>ac",  -- open the persistent chat window
    add_context = "<leader>af",  -- add or manage context files via telescope
    submit      = "<CR>",        -- confirm in the input window
    close       = "<Esc>",       -- dismiss the input window
  },

  -- UI tweaks -------------------------------------------------------------
  ui = {
    border           = "rounded",   -- any nvim_open_win border style
    title            = " Nudge ",
    title_pos        = "center",
    width            = 0.6,         -- fraction of editor columns
    spinner_frames   = { "⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏" },
    spinner_interval = 80,          -- ms between spinner frames

    -- Typewriter effect: AI output is revealed at a fixed character rate,
    -- similar to ChatGPT. Increase chars_per_tick to speed up, decrease to slow down.
    typewriter_chars_per_tick = 2,  -- characters revealed per timer tick
    typewriter_interval       = 16, -- ms between ticks
  },

  -- System prompt sent on every inline-prompt and question request --------
  -- Override to add project-specific instructions.
  system_prompt = [[
You are an expert coding assistant embedded inside a code editor.
When generating or modifying code, output ONLY the raw code.
Do NOT wrap the output in markdown code fences (``` blocks).
Do NOT add explanations, comments, or any text beyond the code itself.
Preserve the indentation style of any code provided as context.
  ]],

  -- System prompt used in the chat and question windows ------------------
  chat_system_prompt = [[
You are a helpful coding assistant integrated into a code editor.
Answer questions clearly and concisely.
You may use markdown formatting in your responses, including code blocks.
Keep your answers focused and practical.
  ]],
})
````

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

Your active subscription (Claude Code subscription, API credits, etc.) is used automatically. No API key is needed in the plugin config.

> **Note:** The `claude_cli` provider does not stream tokens. It shows a spinner while the request runs and inserts the full response when done.

---

## Usage

| Mode   | Keys         | Behaviour                                                      |
| ------ | ------------ | -------------------------------------------------------------- |
| Normal | `<leader>aa` | Open inline prompt, insert generated code below the cursor     |
| Visual | `<leader>aa` | Open inline prompt, replace selected lines with generated code |
| Normal | `<leader>ac` | Open the persistent chat window                                |
| Normal | `<leader>af` | Add files to context or manage the current context file list   |
| Input  | `<Enter>`    | Submit the prompt                                              |
| Input  | `<Esc>`      | Cancel or close the window                                     |

### Commands

| Command              | Description                                       |
| -------------------- | ------------------------------------------------- |
| `:Nudge`             | Open the inline AI prompt                         |
| `:NudgeChat`         | Open the persistent chat window                   |
| `:NudgeChatClear`    | Clear the chat history for the current session    |
| `:NudgeContext`      | Add or manage context files via telescope         |
| `:NudgeContextClear` | Clear all context files without opening telescope |

### File context

Use `<leader>af` (or `:NudgeContext`) to attach additional files to every AI request. The contents of all context files are prepended to the prompt, giving the model awareness of code that lives outside the buffer you are currently editing.

When no files are loaded, the telescope file picker opens so you can add one immediately. When files are already loaded, a context-manager picker appears instead:

| Key     | Action                                        |
| ------- | --------------------------------------------- |
| `<CR>`  | Open the selected file in the editor          |
| `<C-d>` | Remove the selected file from the context     |
| `<C-a>` | Clear all context files and close the picker  |
| `<C-n>` | Add another file, switches to the file picker |

Context files persist for the duration of the Neovim session. Use `:NudgeContextClear` to reset them at any time.

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

**Chat with the model**

Press `<leader>ac` to open the chat window. Ask questions about the current file, architecture decisions, or anything else. The conversation persists across open and close until you call `:NudgeChatClear` or restart Neovim.

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

1. Keep modules focused. `config.lua`, `api.lua`, `ui.lua` each own one concern.
2. Run `make lint` and `make test` before opening a PR.
3. No external Lua runtime dependencies beyond `plenary` for tests.
