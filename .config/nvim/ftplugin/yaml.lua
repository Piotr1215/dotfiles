-- Basic Settings
vim.opt_local.cursorcolumn = true -- Highlight the current column
vim.opt_local.shiftwidth = 2 -- Number of spaces to use for each step of (auto)indent
vim.opt_local.softtabstop = 2 -- Number of spaces that a <Tab> counts for while performing editing operations
vim.opt_local.tabstop = 2 -- Number of spaces that a <Tab> in the file counts for
vim.opt_local.expandtab = true -- Expand tab to 2 spaces

-- Helpers
vim.api.nvim_buf_set_keymap(0, "n", "<leader>yt", ":YAMLTelescope<CR>", { noremap = false })
vim.api.nvim_buf_set_keymap(0, "n", "<leader>yl", ":!yamllint %<CR>", { noremap = true, silent = true })

-- Folding
vim.opt_local.foldmethod = "indent"
vim.opt_local.foldlevel = 1
-- ~/.config/nvim/lua/user_functions/keybindings.lua
vim.api.nvim_buf_set_keymap(
  0,
  "n",
  "zj",
  ':lua require("user_functions.navigate_folds").NavigateFold("j")<CR>',
  { noremap = true, silent = true }
)
vim.api.nvim_buf_set_keymap(
  0,
  "n",
  "zk",
  ':lua require("user_functions.navigate_folds").NavigateFold("k")<CR>',
  { noremap = true, silent = true }
)
-- Set up the mapping for YAML files
vim.api.nvim_buf_set_keymap(
  0,
  "n",
  "]]",
  ":lua require('user_functions.yaml_helper').goto_next_same_indent()<CR>",
  { noremap = true, silent = true, desc = "Go to next block at same indent" }
)
vim.api.nvim_buf_set_keymap(
  0,
  "n",
  "[[",
  ":lua require('user_functions.yaml_helper').goto_prev_same_indent()<CR>",
  { noremap = true, silent = true, desc = "Go to next block at same indent" }
)
-- LSP Configuration
require("lspconfig").yamlls.setup {
  settings = {
    yaml = {
      schemas = {
        kubernetes = "k8s-*.yaml",
        ["http://json.schemastore.org/github-workflow"] = ".github/workflows/*",
        ["http://json.schemastore.org/github-action"] = ".github/action.{yml,yaml}",
        ["http://json.schemastore.org/ansible-stable-2.9"] = "roles/tasks/**/*.{yml,yaml}",
        ["http://json.schemastore.org/prettierrc"] = ".prettierrc.{yml,yaml}",
        ["http://json.schemastore.org/kustomization"] = "kustomization.{yml,yaml}",
        ["http://json.schemastore.org/chart"] = "Chart.{yml,yaml}",
        ["http://json.schemastore.org/circleciconfig"] = ".circleci/**/*.{yml,yaml}",
      },
    },
  },
}

-- Autocompletion
local cmp = require "cmp"
cmp.setup.buffer {
  sources = {
    { name = "vsnip" },
    { name = "nvim_lsp" },
    { name = "path" },
    {
      name = "buffer",
      option = {
        get_bufnrs = function()
          local bufs = {}
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            bufs[vim.api.nvim_win_get_buf(win)] = true
          end
          return vim.tbl_keys(bufs)
        end,
      },
    },
  },
}
