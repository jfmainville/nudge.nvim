local config = require("nudge.config")

describe("nudge.config", function()
	describe("defaults", function()
		it("has api_key as default provider", function()
			assert.equals("api_key", config.defaults.auth.provider)
		end)

		it("has nil api_key by default (relies on env var)", function()
			assert.is_nil(config.defaults.auth.api_key)
		end)

		it("has a non-empty model", function()
			assert.is_string(config.defaults.model)
			assert.truthy(#config.defaults.model > 0)
		end)

		it("has positive max_tokens", function()
			assert.is_number(config.defaults.max_tokens)
			assert.truthy(config.defaults.max_tokens > 0)
		end)

		it("has spinner_frames as a non-empty table", function()
			assert.is_table(config.defaults.ui.spinner_frames)
			assert.truthy(#config.defaults.ui.spinner_frames > 0)
		end)

		it("has a non-empty system_prompt", function()
			assert.is_string(config.defaults.system_prompt)
			assert.truthy(#config.defaults.system_prompt > 0)
		end)

		it("has keymaps.prompt defined", function()
			assert.is_string(config.defaults.keymaps.prompt)
			assert.truthy(#config.defaults.keymaps.prompt > 0)
		end)
	end)

	describe("resolve()", function()
		it("returns defaults when called with no args", function()
			local resolved = config.resolve()
			assert.equals(config.defaults.model, resolved.model)
			assert.equals(config.defaults.max_tokens, resolved.max_tokens)
		end)

		it("merges user options over defaults", function()
			local resolved = config.resolve({ model = "claude-haiku-4-5-20251001" })
			assert.equals("claude-haiku-4-5-20251001", resolved.model)
			-- untouched defaults still present
			assert.equals(config.defaults.max_tokens, resolved.max_tokens)
		end)

		it("deep-merges nested tables", function()
			local resolved = config.resolve({ auth = { provider = "claude_cli" } })
			assert.equals("claude_cli", resolved.auth.provider)
			-- api_key default still nil
			assert.is_nil(resolved.auth.api_key)
		end)

		it("does not mutate defaults", function()
			config.resolve({ model = "changed" })
			assert.not_equals("changed", config.defaults.model)
		end)

		it("allows overriding keymaps", function()
			local resolved = config.resolve({ keymaps = { prompt = "<leader>ai" } })
			assert.equals("<leader>ai", resolved.keymaps.prompt)
		end)

		it("allows overriding system_prompt", function()
			local custom = "My custom prompt"
			local resolved = config.resolve({ system_prompt = custom })
			assert.equals(custom, resolved.system_prompt)
		end)

		it("accepts claude_cli provider", function()
			local resolved = config.resolve({ auth = { provider = "claude_cli" } })
			assert.equals("claude_cli", resolved.auth.provider)
		end)

		it("accepts api_key in auth table", function()
			local resolved = config.resolve({ auth = { api_key = "sk-test-key" } })
			assert.equals("sk-test-key", resolved.auth.api_key)
		end)
	end)
end)
