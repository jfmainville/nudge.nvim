local M = {}
M.__index = M

function M.new(render_fn, opts)
	opts = opts or {}
	return setmetatable({
		render_fn      = render_fn,
		chars_per_tick = opts.chars_per_tick or 4,
		interval       = opts.interval or 16,
		pending        = "",
		displayed      = "",
		_timer         = nil,
	}, M)
end

function M:push(text)
	self.pending = self.pending .. text
	if not self._timer then
		self._timer = vim.fn.timer_start(self.interval, function()
			self:_tick()
		end, { ["repeat"] = -1 })
	end
end

function M:finish(on_complete)
	self._done        = true
	self._on_complete = on_complete
	if not self._timer then
		self:_complete()
	end
end

function M:abort()
	if self._timer then
		vim.fn.timer_stop(self._timer)
		self._timer = nil
	end
end

function M:_tick()
	if self.pending == "" then
		if self._done then
			vim.fn.timer_stop(self._timer)
			self._timer = nil
			self:_complete()
		end
		return
	end

	self.displayed = self.displayed .. self.pending:sub(1, self.chars_per_tick)
	self.pending   = self.pending:sub(self.chars_per_tick + 1)
	self.render_fn(self.displayed)
end

function M:_complete()
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
