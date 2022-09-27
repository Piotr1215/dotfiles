local set = vim.opt
local vcmd = vim.cmd

vcmd('syntax on')
vcmd('syntax enable')
vcmd('filetype on')
vcmd('filetype plugin indent on')
vcmd('set clipboard=unnamedplus')
vcmd('set winbar=%=%m\\ %f')
vcmd('set completefunc=emoji#complete')
vcmd('set wildignore+=*/tmp/*,*.so,*.swp,*.zip')
vcmd('set backspace=indent,eol,start')
vcmd('set foldexpr=getline(v:lnum)=~\'^\\s*$\'&&getline(v:lnum+1)=~\'\\S\'?\'<1\':1')
vcmd('set jumpoptions=view')

--Remap for dealing with word wrap
set.background = 'dark'
set.ignorecase = true -- ignore case in search
set.smartcase = true -- do not ignore case with capitals
set.scrolloff = 8
set.hlsearch = true
set.updatetime = 300
set.splitright = true -- put new splits to the right
set.splitbelow = true -- put new splits below
set.lazyredraw = true -- do not redraw for macros, faster execution
set.undofile = true -- persistent undo even after session close

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
