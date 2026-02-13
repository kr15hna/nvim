return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.explorer = opts.explorer or {}
      opts.explorer.enabled = false
    end,
    keys = {
      { "<leader>e", false }, -- remove Snacks explorer mapping
      { "<leader>E", false }, -- (optional) remove any related mapping
    },
  },
}
