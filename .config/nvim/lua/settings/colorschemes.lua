-- Colorschemes settings
require("catppuccin").setup {
  flavour = "mocha",
  transparent_background = false,
  term_colors = true,
  -- color_overrides = {
  -- mocha = {
  -- base = "#000000",
  -- mantle = "#000000",
  -- crust = "#000000",
  -- },
  -- },
  integrations = {
    cmp = true,
    treesitter = true,
    notify = true,
    telescope = true,
  },
}

require("tokyonight").setup {
  style = "night", -- The theme comes in three styles, `storm`, a darker variant `night` and `day`
  transparent = false, -- Enable this to disable setting the background color
  terminal_colors = true,
}

require("nightfox").setup {
  options = {
    transparent = false,
    terminal_colors = true,
    dim_inactive = true,
  },
  modules = {
    telescope = true,
    treesitter = true,
    gitgutter = true,
  },
}

vim.cmd [[
let g:PaperColor_Theme_Options = {
  \   'theme': {
  \     'default.dark': {
  \       'transparent_background': 0
  \     }
  \   }
  \ }
]]

require("transparent").setup {
  extra_groups = { -- table/string: additional groups that should be cleared
    -- In particular, when you set it to 'all', that means all available groups
    -- example of akinsho/nvim-bufferline.lua
    "BufferLineTabClose",
    "BufferlineBufferSelected",
    "BufferLineFill",
    "BufferLineBackground",
    "BufferLineSeparator",
    "BufferLineIndicatorSelected",
    "Telescope",
  },
}

-- Moonfly
local winhighlight = {
  winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:PmenuSel",
}

vim.g.moonflyNormalFloat = true
vim.g.moonflyWinSeparator = 2
vim.g.moonflyTransparent = true
vim.opt.fillchars = {
  horiz = "━",
  horizup = "┻",
  horizdown = "┳",
  vert = "┃",
  vertleft = "┫",
  vertright = "┣",
  verthoriz = "╋",
}
vim.g.termigurcolors = true
-- Active colorscheme
-- vim.cmd('colorscheme moonfly')
vim.cmd "colorscheme catppuccin"
-- vim.cmd('colorscheme nightfox')
-- vim.cmd('colorscheme tokyonight-night')
-- vim.cmd('colorscheme carbonfox')
