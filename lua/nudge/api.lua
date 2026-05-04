local M = {}

--- Build the messages array sent to the API.
---@param prompt string        User's instruction
---@param context string       Visual selection text (may be empty)
---@param filetype string      Buffer filetype
---@param file table|nil       { name: string, content: string, cursor_row: number }
---@return table
function M.build_messages(prompt, context, filetype, file)
	local parts = {}
	local ft = filetype or "text"

	if file and file.content ~= "" then
		local label = (file.name ~= "" and file.name) or "[No Name]"
		table.insert(parts, ("File: %s  (filetype: %s)"):format(label, ft))
		table.insert(parts, file.content)
		table.insert(parts, "---")
	end

	local output_rule
	if context and context ~= "" then
		table.insert(
			parts,
			("Selected code to replace (lines %d-%d):"):format(file and file.sel_sr or 0, file and file.sel_er or 0)
		)
		table.insert(parts, context)
		table.insert(parts, "---")
		output_rule = "Output ONLY the replacement lines. Do not include the rest of the file."
	elseif file and file.cursor_row then
		table.insert(parts, ("Cursor is at line %d."):format(file.cursor_row))
		table.insert(parts, "---")
		output_rule = "Output ONLY the new lines to insert. Do not include any existing file content."
	else
		output_rule = "Output ONLY the requested code. Do not include any surrounding context."
	end

	table.insert(parts, "Instruction: " .. prompt)
	table.insert(parts, output_rule)

	return { { role = "user", content = table.concat(parts, "\n") } }
end

-- ---------------------------------------------------------------------------
-- Anthropic SSE streaming (api_key provider)
-- ---------------------------------------------------------------------------

local function build_api_cmd(config, messages)
	local key = config.auth.api_key or vim.env.ANTHROPIC_API_KEY
	if not key or key == "" then
		return nil, "No API key found. Set auth.api_key or the ANTHROPIC_API_KEY env var."
	end
	local body = vim.json.encode({
		model = config.model,
		max_tokens = config.max_tokens,
		system = config.system_prompt,
		stream = true,
		messages = messages,
	})
	return {
		"curl",
		"-sN",
		"-X",
		"POST",
		"https://api.anthropic.com/v1/messages",
		"-H",
		"x-api-key: " .. key,
		"-H",
		"anthropic-version: 2023-06-01",
		"-H",
		"content-type: application/json",
		"-d",
		body,
	},
		nil
end

local function parse_sse(line)
	if line:sub(1, 6) ~= "data: " then
		return nil, false
	end
	local json_str = line:sub(7)
	if json_str == "" then
		return nil, false
	end
	local ok, event = pcall(vim.json.decode, json_str)
	if not ok or not event then
		return nil, false
	end
	if
		event.type == "content_block_delta"
		and event.delta
		and event.delta.type == "text_delta"
		and event.delta.text
	then
		return event.delta.text, false
	end
	if event.type == "message_stop" then
		return nil, true
	end
	return nil, false
end

local function stream_api(config, messages, on_token, on_done, on_error)
	local cmd, err = build_api_cmd(config, messages)
	if err then
		on_error(err)
		return nil
	end

	local done_fired = false

	return vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				local text, stop = parse_sse(line)
				if text and text ~= "" then
					vim.schedule(function()
						on_token(text)
					end)
				end
				if stop and not done_fired then
					done_fired = true
					vim.schedule(on_done)
				end
			end
		end,
		on_stderr = function(_, data)
			local msg = table.concat(
				vim.tbl_filter(function(l)
					return l ~= ""
				end, data),
				"\n"
			)
			if msg ~= "" then
				vim.schedule(function()
					on_error(msg)
				end)
			end
		end,
		on_exit = function(_, code)
			if not done_fired then
				done_fired = true
				vim.schedule(function()
					if code ~= 0 then
						on_error(("curl exited with code %d"):format(code))
					else
						on_done()
					end
				end)
			end
		end,
	})
end

-- ---------------------------------------------------------------------------
-- Claude CLI provider (OAuth / Pro subscription)
-- ---------------------------------------------------------------------------

local function stream_cli(config, messages, on_token, on_done, on_error)
	local prompt = messages[#messages].content
	local cmd = {
		"claude",
		"--print",
		prompt,
		"--output-format",
		"text",
		"--model",
		config.model,
	}

	local done_fired = false
	local accumulated = {}

	return vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(accumulated, line)
					vim.schedule(function()
						on_token(line .. "\n")
					end)
				end
			end
		end,
		on_stderr = function(_, data)
			local msg = table.concat(
				vim.tbl_filter(function(l)
					return l ~= ""
				end, data),
				"\n"
			)
			if msg ~= "" then
				vim.schedule(function()
					on_error(msg)
				end)
			end
		end,
		on_exit = function(_, code)
			if not done_fired then
				done_fired = true
				vim.schedule(function()
					if code ~= 0 then
						on_error(("claude CLI exited with code %d"):format(code))
					else
						on_done()
					end
				end)
			end
		end,
	})
end

-- ---------------------------------------------------------------------------
-- Public interface
-- ---------------------------------------------------------------------------

---@param config table
---@param messages table
---@param on_token fun(text: string)
---@param on_done fun()
---@param on_error fun(err: string)
---@return number|nil job_id
function M.stream(config, messages, on_token, on_done, on_error)
	if config.auth.provider == "claude_cli" then
		return stream_cli(config, messages, on_token, on_done, on_error)
	end
	return stream_api(config, messages, on_token, on_done, on_error)
end

return M
