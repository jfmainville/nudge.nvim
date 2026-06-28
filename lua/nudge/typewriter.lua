-- Typewriter: reveals streamed text character-by-character at a fixed rate,
-- creating a smooth "ChatGPT-style" typing effect independent of API token
-- arrival timing.

local M = {}
M.__index = M

-- render_fn(text)   called each tick with the full displayed text so far
-- opts:
--   chars_per_tick  chars to reveal per timer tick (default 4)
--   interval        ms between ticks (default 16 ≈ 60 fps)
function M.new(render_fn, opts)
	opts = opts or {}
	local self = setmetatable({
		render_fn      = render_fn,
		chars_per_tick = opts.chars_per_tick or 4,
		interval       = opts.interval or 16,
		pending        = "",
		displayed      = "",
		_done          = false,
		_on_complete   = nil,
		_timer         = nil,
	}, M)
	return self
end

-- Called for each incoming token from the API stream.
function M:push(text)
	self.pending = self.pending .. text
	if not self._timer then
		self:_start()
	end
end

-- Called when the API stream ends. on_complete(full_text) fires once the
-- queue has been drained and all text is visible.
function M:finish(on_complete)
	self._done        = true
	self._on_complete = on_complete
	-- If nothing is pending the timer may already be stopped; flush now.
	if not self._timer then
		self:_complete()
	end
end

-- Immediately stop the timer and discard any pending text (e.g. on error).
function M:abort()
	if self._timer then
		vim.fn.timer_stop(self._timer)
		self._timer = nil
	end
end

-- Return the full text that has been revealed so far.
function M:current()
	return self.displayed
end

-- -------------------------------------------------------------------------
-- Internal
-- -------------------------------------------------------------------------

function M:_start()
	self._timer = vim.fn.timer_start(self.interval, function()
		self:_tick()
	end, { ["repeat"] = -1 })
end

function M:_tick()
	if self.pending == "" then
		if self._done then
			vim.fn.timer_stop(self._timer)
			self._timer = nil
			vim.schedule(function()
				self:_complete()
			end)
		end
		-- else: waiting for more tokens — keep timer running
		return
	end

	local chunk        = self.pending:sub(1, self.chars_per_tick)
	self.pending       = self.pending:sub(self.chars_per_tick + 1)
	self.displayed     = self.displayed .. chunk

	local snap = self.displayed
	vim.schedule(function()
		self.render_fn(snap)
	end)
end

function M:_complete()
	-- Flush any remaining text (safety net; normally drained by timer).
	if self.pending ~= "" then
		self.displayed = self.displayed .. self.pending
		self.pending   = ""
		self.render_fn(self.displayed)
	end
	if self._on_complete then
		self._on_complete(self.displayed)
	end
end

return M
