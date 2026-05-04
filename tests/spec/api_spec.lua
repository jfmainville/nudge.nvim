local api = require("nudge.api")

describe("nudge.api", function()
  describe("build_messages()", function()
    it("creates a single user message with just the prompt", function()
      local msgs = api.build_messages("refactor this", "", "lua")
      assert.equals(1, #msgs)
      assert.equals("user", msgs[1].role)
      assert.equals("refactor this", msgs[1].content)
    end)

    it("includes context and filetype when context is provided", function()
      local msgs = api.build_messages("add error handling", "local x = 1", "lua")
      assert.equals(1, #msgs)
      local content = msgs[1].content
      assert.truthy(content:find("add error handling"))
      assert.truthy(content:find("lua"))
      assert.truthy(content:find("local x = 1"))
    end)

    it("handles nil context gracefully", function()
      local msgs = api.build_messages("write a test", nil, "python")
      assert.equals(1, #msgs)
      assert.equals("write a test", msgs[1].content)
    end)

    it("handles nil filetype gracefully", function()
      local msgs = api.build_messages("write a test", "some code", nil)
      assert.equals(1, #msgs)
      local content = msgs[1].content
      assert.truthy(content:find("text")) -- fallback filetype
    end)

    it("uses last message as prompt in multi-context scenario", function()
      local msgs = api.build_messages("explain this", "def foo(): pass", "python")
      assert.equals("user", msgs[#msgs].role)
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
      api.stream(cfg, { { role = "user", content = "test" } },
        function() end,
        function() end,
        function(err) error_msg = err end
      )

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
      api.stream(cfg_api, { { role = "user", content = "hi" } },
        function() end,
        function() end,
        function() got_error = true end
      )

      vim.env.ANTHROPIC_API_KEY = saved
      assert.is_true(got_error)
    end)
  end)
end)
