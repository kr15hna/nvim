-- return {
--   "rest-nvim/rest.nvim",
--   dependencies = {
--     "nvim-treesitter/nvim-treesitter",
--     opts = function(_, opts)
--       opts.ensure_installed = opts.ensure_installed or {}
--       table.insert(opts.ensure_installed, "http")
--     end,
--   },
-- }

-- return {
--   "rest-nvim/rest.nvim",
--   opts = {
--     rocks = {
--       enabled = false, -- simplest: don’t do any luarocks
--       -- or: keep rocks but don’t use hererocks; depends on your setup
--       -- hererocks = false,
--     },
--   },
-- }

return {
  -- "rest-nvim/rest.nvim",
  -- rocks = { enabled = false }, -- <-- top-level, NOT inside opts
  -- config = function()
  --   require("rest-nvim").setup({})
  -- end,
}
