std = "luajit"
globals = { "vim" }
read_globals = { "vim" }

-- Test globals
files["tests/"] = {
  globals = { "describe", "it", "assert", "before_each", "after_each", "pending" },
}

-- Ignore line length (handled by stylua)
max_line_length = false

-- Ignore unused self in methods
self = false
