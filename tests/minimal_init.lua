-- Minimal Neovim init for running tests with plenary.nvim
-- Usage: nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/spec {minimal_init = 'tests/minimal_init.lua'}"

-- Add the plugin itself to runtimepath
vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))

-- Add plenary if it's installed in common locations
local plenary_paths = {
  vim.fn.stdpath("data") .. "/lazy/plenary.nvim",
  vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim",
  vim.fn.stdpath("data") .. "/plugged/plenary.nvim",
}

for _, p in ipairs(plenary_paths) do
  if vim.fn.isdirectory(p) == 1 then
    vim.opt.rtp:prepend(p)
    break
  end
end

-- Load plenary
pcall(vim.cmd, "runtime! plugin/plenary.vim")
