-- Colorschemes settings
require("catppuccin").setup({
  transparent_background = false,
  term_colors = true,
})

require("tokyonight").setup({
  style = "night", -- The theme comes in three styles, `storm`, a darker variant `night` and `day`
  transparent = false, -- Enable this to disable setting the background color
  terminal_colors = true,
})

require('nightfox').setup({
  options = {
    transparent = true,
    terminal_colors = true,
    dim_inactive = true,
  },
  modules = {
    telescope = true,
    treesitter = true,
    lsp_saga = true,
    gitgutter = true,
  }
})

vim.cmd [[
let g:PaperColor_Theme_Options = {
  \   'theme': {
  \     'default.dark': {
  \       'transparent_background': 0
  \     }
  \   }
  \ }
]]

-- Active colorscheme
vim.cmd('colorscheme nightfox')
