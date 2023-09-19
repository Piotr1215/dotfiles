local set = vim.opt
local vcmd = vim.cmd

vcmd('syntax on')
vcmd('syntax enable')
vcmd('filetype on')
vcmd('filetype plugin indent on')
vcmd('set clipboard=unnamedplus')
vcmd('set winbar=%=%m%F')
vcmd('set completefunc=emoji#complete')
vcmd('set wildignore+=*/tmp/*,*.so,*.swp,*.zip')
vcmd('set backspace=indent,eol,start')
vcmd('set jumpoptions=view')
vcmd('set sessionoptions+=tabpages,globals')

-- Treesitter folding
vim.wo.foldmethod = 'expr'
vim.wo.foldexpr = 'nvim_treesitter#foldexpr()'
vim.api.nvim_set_option('updatetime', 300)

-- Fixed column for diagnostics to appear
-- Show autodiagnostic popup on cursor hover_range
-- Goto previous / next diagnostic warning / error
-- Show inlay_hints more frequently
vim.cmd([[
set signcolumn=yes
autocmd CursorHold * lua vim.diagnostic.open_float(nil, { focusable = false })
]])

--Remap for dealing with word wrap
set.completeopt = { 'menuone', 'noselect', 'noinsert' }
set.shortmess = set.shortmess + { c = true }
set.background = 'dark'
set.ignorecase = true -- ignore case in search
set.smartcase = true  -- do not ignore case with capitals
set.scrolloff = 8
set.hlsearch = true
set.updatetime = 300
set.splitright = true -- put new splits to the right
set.splitbelow = true -- put new splits below
set.lazyredraw = true -- do not redraw for macros, faster execution
set.undofile = true   -- persistent undo even after session close

set.number = true
set.encoding = "utf-8"
set.cursorline = true

set.expandtab = true
set.shiftwidth = 2
set.softtabstop = 2
set.autoindent = true
set.relativenumber = true
set.incsearch = true
set.laststatus = 2
set.cmdheight = 1
