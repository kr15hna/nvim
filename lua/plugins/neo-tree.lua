-- return {
--   {
--     "nvim-neo-tree/neo-tree.nvim",
--     enabled = true,
--     keys = {
--       { "<leader>e", "<cmd>Neotree toggle<cr>", desc = "Explorer (Neo-tree)" },
--     },
--   },
-- }

return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    keys = {
      { "<leader>e", "<cmd>Neotree toggle<cr>", desc = "Explorer (Neo-tree)" },
    },
    opts = function(_, opts)
      opts = opts or {}
      opts.filesystem = opts.filesystem or {}
      opts.filesystem.hijack_netrw_behavior = "open_default"

      opts.filesystem.filtered_items = opts.filesystem.filtered_items or {}
      opts.filesystem.filtered_items.hide_dotfiles = false
      opts.filesystem.filtered_items.hide_hidden = false
      opts.filesystem.filtered_items.hide_gitignored = false
      opts.filesystem.filtered_items.hide_ignored = false

      return opts
    end,
  },
}
