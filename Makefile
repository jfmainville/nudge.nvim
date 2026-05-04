.PHONY: test lint

# Run tests with plenary.nvim
# Requires nvim and plenary.nvim installed (e.g. via lazy.nvim)
test:
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/spec {minimal_init = 'tests/minimal_init.lua'}"

# Lint with luacheck
lint:
	luacheck lua/ tests/ \
		--globals vim describe it assert before_each after_each \
		--no-unused-args

# Stylua format check
fmt-check:
	stylua --check lua/ tests/

# Stylua format
fmt:
	stylua lua/ tests/
