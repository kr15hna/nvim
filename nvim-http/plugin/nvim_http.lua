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
  end,
})
