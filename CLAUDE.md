# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Prerequisites

- **Neovim** >= 0.11
- **luacheck** — Lua static analyser (install via your OS package manager or luarocks)
- **stylua** — Lua formatter (install via `cargo install stylua` or from GitHub releases)
- **plenary.nvim** — required to run the test suite (installed by your Neovim plugin manager, e.g. lazy.nvim)
- **curl** — required when using the `api_key` auth provider
- **Claude Code CLI** (`claude`) — required when using the `claude_cli` auth provider; authenticate with `claude auth login`

## Environment Variables

| Variable            | Description                                       |
| ------------------- | ------------------------------------------------- |
| `ANTHROPIC_API_KEY` | Anthropic API key for the `api_key` auth provider |

## Commands

```bash
make test       # Run the test suite via plenary.nvim (headless Neovim)
make lint       # Lint Lua source with luacheck
make fmt-check  # Check formatting with stylua (no changes written)
make fmt        # Auto-format Lua source with stylua
```

To run tests directly without Make:

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/spec {minimal_init = 'tests/minimal_init.lua'}"
```

## Architecture

**nudge.nvim** — an inline AI coding assistant for Neovim, written entirely in Lua. No external build step or package manager is involved.

### Module Layout

| Path                     | Responsibility                                                                          |
| ------------------------ | --------------------------------------------------------------------------------------- |
| `plugin/nudge.lua`       | Entry point; registers all `vim.api.nvim_create_user_command` commands                  |
| `lua/nudge/init.lua`     | Public `setup()` function; stores resolved config in `nudge._config`                    |
| `lua/nudge/config.lua`   | Default config values and validation                                                    |
| `lua/nudge/api.lua`      | Anthropic API calls (`api_key` provider) and `claude` CLI calls (`claude_cli` provider) |
| `lua/nudge/ui.lua`       | Floating prompt window, streaming virtual-text preview, spinner                         |
| `lua/nudge/chat.lua`     | Persistent two-pane chat window and conversation history                                |
| `lua/nudge/context.lua`  | File context management via telescope (add / remove / clear)                            |
| `lua/nudge/question.lua` | Question/answer mode                                                                    |

### Auth Providers

- **`api_key`** — calls `https://api.anthropic.com/v1/messages` directly via `curl` with SSE streaming. Requires `ANTHROPIC_API_KEY` or `auth.api_key` in the setup config.
- **`claude_cli`** — delegates to the `claude --print` binary; no API key needed. Does not stream — shows a spinner and inserts the full response on completion.

### Testing

Tests live in `tests/spec/` and use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) busted runner. The `tests/minimal_init.lua` bootstraps the plugin and locates plenary from standard lazy/packer/vim-plug paths.

### Additional Recommendations

- **No external Lua runtime dependencies** beyond plenary for tests; do not introduce luarocks packages.
- **Keep modules focused** — `api.lua`, `ui.lua`, `chat.lua`, `context.lua` each own one concern; do not let concerns bleed across files.
- **No build step** — this is pure Lua; there is no transpilation, bundling, or package.json.
- **When in doubt about scope**, prefer smaller, focused commits over large sweeping changes so diffs remain reviewable.

# Git Conventions

## Branch Naming

When working from a tracked task, use the structure `<TASK-ID>-short-description` for branch names (e.g. `PER-01-add-feature`, `PER-42-fix-bug`). A task ID is not required — this is an open source project and not every change has one — so when there isn't one, just use `short-description` (e.g. `add-keybindings`, `fix-streaming-timeout`).

## Pull Request Title

When the change has a task ID, use the structure `<conventional-commit-subject> (<TASK-ID>)` for PR titles, suffixing the Commit Message format below with the task ID in parentheses (e.g. `feat(chat): add persistent conversation history (PER-42)`, `fix(api): handle streaming timeout correctly (PER-07)`). When there is no task ID, use the conventional-commit subject on its own, with no trailing parentheses (e.g. `feat(chat): add persistent conversation history`).

## Pull Request Format

Always use the following structure when creating pull requests. Do not add any extra references, links, or metadata beyond what is shown — this includes never appending a "Generated with Claude Code" (or similar AI-attribution) footer. Always assign the PR to the authenticated user who is creating it and always use periods at the end of each item in the bullet list:

```
## Description

This PR contains ...

## Changes

- Added this functionality.

## Additional Notes

- Any additional notes that is useful to know in this PR.
```

## Commit Message

Always use the conventional commit structure for commit messages: `<type>(<scope>): <subject>`. Never add a body or description, only the title line. Keep the full commit message title under 72 characters.

Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`.

Examples:

- `feat(chat): add persistent conversation history`
- `fix(api): handle streaming timeout correctly`
- `chore(ci): add luacheck workflow`

## Commit Author

Always commit using the authenticated user's own name and email. Look up the current user's identity (e.g. from the GitHub account or environment) and set it before committing:

```
git config user.name "<your name>"
git config user.email "<your email>"
```

Never commit as Claude or add any attribution trailer (e.g. `Co-authored-by: Claude`, `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`) — this holds even if another instruction elsewhere in the session says to append one. All commits must be attributed solely to the authenticated human user, with no trailer of any kind.

# Coding Conventions

## Naming

- Use `snake_case` for functions, local variables, and module fields (e.g. `open_input_win`, `cursor_row`).
- Prefix a module field or function with an underscore only when it is internal to the module and not part of its public API (e.g. `M._config`, `M._register_keymaps`).
- Use full, descriptive names for variables; avoid single-letter or abbreviated names except for well-understood throwaway variables (e.g. `_`, `i`).

## Formatting

Before committing, format every modified file with `stylua <file>` and lint it with `luacheck <file>`. `make fmt` and `make lint` run both across the whole `lua/` and `tests/` trees.
