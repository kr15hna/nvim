-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--


vim.keymap.set("n", "<leader>hr", "<cmd>HttpRun<cr>", { desc = "Run HTTP to cursor" })
vim.keymap.set("n", "<leader>hR", "<cmd>HttpRunAll<cr>", { desc = "Run all HTTP" })
vim.keymap.set("n", "<leader>hh", "<cmd>HttpHistory<cr>", { desc = "Open HTTP history" })
vim.keymap.set("n", "<leader>ha", "<cmd>HttpPickDesiredAccount<cr>", { desc = "Switch account" })

