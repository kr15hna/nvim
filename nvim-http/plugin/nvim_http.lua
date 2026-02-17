if vim.g.loaded_nvim_http == 1 then
  return
end

vim.g.loaded_nvim_http = 1

require("nvim_http").setup()

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.http",
  callback = function()
    if vim.bo.filetype == "" then
      vim.bo.filetype = "http"
    end
    if vim.bo.syntax == "" then
      vim.bo.syntax = "http"
    end
    if vim.treesitter and vim.treesitter.stop then
      pcall(vim.treesitter.stop, vim.api.nvim_get_current_buf())
    end
  end,
})
