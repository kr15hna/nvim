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
      opts.filesystem.follow_current_file = opts.filesystem.follow_current_file or {}
      opts.filesystem.follow_current_file.enabled = true
      opts.filesystem.window = opts.filesystem.window or {}
      opts.filesystem.window.mappings = opts.filesystem.window.mappings or {}
      opts.filesystem.window.mappings["/"] = "none"
      opts.filesystem.window.mappings["Z"] = "expand_all_subnodes"

      opts.filesystem.filtered_items = opts.filesystem.filtered_items or {}
      opts.filesystem.filtered_items.visible = false
      opts.filesystem.filtered_items.hide_by_name = {
        ".git",
        ".cargo",
      }

      opts.filesystem.filtered_items.hide_dotfiles = false
      opts.filesystem.filtered_items.hide_hidden = false
      opts.filesystem.filtered_items.hide_gitignored = false
      opts.filesystem.filtered_items.hide_ignored = false

      return opts
    end,
  },
}
