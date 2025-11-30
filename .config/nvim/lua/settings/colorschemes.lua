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
  palettes = {
    carbonfox = {
      bg1 = "#000000", -- Pure black background
      bg0 = "#0c0c0c", -- Slightly lighter for contrast
      bg2 = "#121212", -- UI elements
      bg3 = "#1a1a1a", -- Selections
    },
  },
  modules = {
    telescope = true,
    treesitter = true,
    gitgutter = true,
  },
}

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
-- vim.cmd "colorscheme moonfly"
-- vim.cmd "colorscheme catppuccin"
-- vim.cmd('colorscheme nightfox')
-- vim.cmd "colorscheme tokyonight-night"
vim.cmd "colorscheme carbonfox"

-- Auto-dim when Neovim loses focus (matches tmux inactive pane color)
vim.api.nvim_create_autocmd("FocusLost", {
  callback = function()
    vim.cmd "highlight Normal guibg=#1a1a1a ctermbg=234"
    vim.cmd "highlight NormalNC guibg=#1a1a1a ctermbg=234"
    vim.cmd "highlight StatusLine guibg=#1a1a1a ctermbg=234"
    vim.cmd "highlight StatusLineNC guibg=#1a1a1a ctermbg=234"
    vim.cmd "highlight TabLine guibg=#1a1a1a ctermbg=234"
    vim.cmd "highlight TabLineFill guibg=#1a1a1a ctermbg=234"
    vim.cmd "highlight WinBar guibg=#1a1a1a ctermbg=234"
    vim.cmd "highlight WinBarNC guibg=#1a1a1a ctermbg=234"
  end,
})

vim.api.nvim_create_autocmd("FocusGained", {
  callback = function()
    vim.cmd "highlight Normal guibg=#000000 ctermbg=16"
    vim.cmd "highlight NormalNC guibg=#000000 ctermbg=16"
    vim.cmd "highlight StatusLine guibg=#000000 ctermbg=16"
    vim.cmd "highlight StatusLineNC guibg=#000000 ctermbg=16"
    vim.cmd "highlight TabLine guibg=#000000 ctermbg=16"
    vim.cmd "highlight TabLineFill guibg=#000000 ctermbg=16"
    vim.cmd "highlight WinBar guibg=#000000 ctermbg=16"
    vim.cmd "highlight WinBarNC guibg=#000000 ctermbg=16"
  end,
})
