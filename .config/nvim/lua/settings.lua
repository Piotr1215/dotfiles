local set = vim.opt
local cmd = vim.cmd

cmd('syntax enable')
cmd('syntax on')
cmd('filetype on')
cmd('filetype plugin indent on')

set.background = 'dark'
set.ignorecase = true             -- ignore case in search
set.smartcase = true              -- do not ignore case with capitals  
set.scrolloff = 8
set.hlsearch = true
set.updatetime = 300
set.autochdir = true

set.splitright = true             -- put new windows below current

set.mouse = v
set.number = true
set.encoding = "utf-8"
set.backspace = indent,eol,start
set.cursorline = true

set.expandtab = true
set.shiftwidth = 5
set.softtabstop = 4
set.autoindent = true
set.relativenumber = true
set.incsearch = true
set.laststatus = 3

cmd('colorscheme PaperColor')
