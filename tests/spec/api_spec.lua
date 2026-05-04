local api = require("nudge.api")

describe("nudge.api", function()
	describe("build_messages()", function()
		it("creates a single user message with just the prompt (no file context)", function()
			local msgs = api.build_messages("refactor this", "", "lua")
			assert.equals(1, #msgs)
			assert.equals("user", msgs[1].role)
			assert.truthy(msgs[1].content:find("refactor this"))
		end)

		it("includes file content when file context is provided", function()
			local file = { name = "foo.lua", content = "local x = 1\nlocal y = 2", cursor_row = 2 }
			local msgs = api.build_messages("add a function", "", "lua", file)
			local content = msgs[1].content
			assert.truthy(content:find("foo.lua"))
			assert.truthy(content:find("local x = 1"))
			assert.truthy(content:find("add a function"))
		end)

		it("includes cursor line hint in normal mode (no selection)", function()
			local file = { name = "bar.py", content = "x = 1", cursor_row = 1, sel_sr = nil, sel_er = nil }
			local msgs = api.build_messages("write a class", "", "python", file)
			local content = msgs[1].content
			assert.truthy(content:find("line 1"))
		end)

		it("includes selection context and line range in visual mode", function()
			local file = { name = "bar.py", content = "x = 1\ny = 2", cursor_row = 1, sel_sr = 1, sel_er = 2 }
			local msgs = api.build_messages("rename vars", "x = 1\ny = 2", "python", file)
			local content = msgs[1].content
			assert.truthy(content:find("rename vars"))
			assert.truthy(content:find("x = 1"))
			assert.truthy(content:find("lines 1%-2") or content:find("lines 1-2"))
		end)

		it("handles nil context gracefully", function()
			local msgs = api.build_messages("write a test", nil, "python")
			assert.equals(1, #msgs)
			assert.truthy(msgs[1].content:find("write a test"))
		end)

		it("handles nil filetype gracefully", function()
			local file = { name = "", content = "some code", cursor_row = 1 }
			local msgs = api.build_messages("explain", "", nil, file)
			local content = msgs[1].content
			assert.truthy(content:find("text")) -- fallback filetype
		end)

		it("handles nil file context (backward compat)", function()
			local msgs = api.build_messages("explain this", "def foo(): pass", "python", nil)
			assert.equals("user", msgs[#msgs].role)
			assert.truthy(msgs[1].content:find("explain this"))
		end)
	end)

	describe("stream() error handling", function()
		it("calls on_error when api_key provider has no key", function()
			-- Remove env var for this test
			local saved = vim.env.ANTHROPIC_API_KEY
			vim.env.ANTHROPIC_API_KEY = nil

			local cfg = {
				auth = { provider = "api_key", api_key = nil },
				model = "claude-opus-4-5",
				max_tokens = 100,
				system_prompt = "test",
			}

			local error_msg = nil
			api.stream(cfg, { { role = "user", content = "test" } }, function() end, function() end, function(err)
				error_msg = err
			end)

			-- Restore
			vim.env.ANTHROPIC_API_KEY = saved

			assert.truthy(error_msg ~= nil)
			assert.truthy(error_msg:lower():find("api key") or error_msg:lower():find("key"))
		end)

		it("dispatches to correct provider", function()
			-- Verify that when provider = "api_key", it tries to build API cmd
			-- We can't run a real request in tests, but we can verify error messages
			local cfg_api = {
				auth = { provider = "api_key", api_key = nil },
				model = "claude-opus-4-5",
				max_tokens = 100,
				system_prompt = "test",
			}

			local saved = vim.env.ANTHROPIC_API_KEY
			vim.env.ANTHROPIC_API_KEY = nil

			local got_error = false
			api.stream(cfg_api, { { role = "user", content = "hi" } }, function() end, function() end, function()
				got_error = true
			end)

			vim.env.ANTHROPIC_API_KEY = saved
			assert.is_true(got_error)
		end)
	end)
end)
