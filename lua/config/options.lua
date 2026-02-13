-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Use spaces instead of tabs
-- vim.opt.expandtab = true
-- vim.opt.tabstop = 2
-- vim.opt.shiftwidth = 2
-- vim.opt.softtabstop = 2

vim.o.showtabline = 0
vim.g.autoformat = false


-- vim.o.statusline = vim.o.statusline .. " %{get(g:,'nvim_http_desired_account','') != '' ? '[LM:' . g:nvim_http_desired_account . ']' : ''}"
-- vim.o.statusline = vim.o.statusline .. " %{get(g:,'nvim_http_desired_account','') != '' ?
--   '[LM:' . g:nvim_http_desired_account . ']' : ''}"

