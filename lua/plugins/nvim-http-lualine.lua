return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    table.insert(opts.sections.lualine_x, 1, {
      function()
        local ok, nvim_http = pcall(require, "nvim_http")
        if not ok then
          return ""
        end
        local acc = nvim_http.current_desired_account()
        return acc ~= "" and ("clientId:" .. acc) or ""
      end,
      color = { fg = "#f9e2af" },
    })
  end,
}
