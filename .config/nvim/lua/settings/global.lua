local set = vim.opt
local vcmd = vim.cmd

vcmd "syntax on"
vcmd "set termguicolors"
vcmd "syntax enable"
vcmd "filetype on"
vcmd "filetype plugin indent on"
vcmd "set clipboard=unnamedplus"
vcmd "set winbar=%=%m%F"

-- Terminal title (shows in tmux pane border)
set.title = true
set.titlestring = "nvim: %t" -- shows "nvim: filename"
vcmd "set completefunc=emoji#complete"
vcmd "set wildignore+=*/tmp/*,*.so,*.swp,*.zip"
vcmd "set backspace=indent,eol,start"
vcmd "set jumpoptions=view"
vcmd "set sessionoptions+=tabpages,globals"
vcmd "set cursorcolumn"

-- Treesitter folding
vim.wo.foldmethod = "expr"
vim.wo.foldexpr = "nvim_treesitter#foldexpr()"
vim.wo.foldenable = false
vcmd "setlocal nofoldenable"
vim.api.nvim_set_option("updatetime", 300)

if vim.g.scroll_fix_enabled == nil then
  vim.g.scroll_fix_enabled = false -- Start with scroll fix disabled
end

-- Disable GitHub Copilot by default
vim.g.copilot_enabled = false
vim.g.openbrowser_default_search = "duckduckgo"

--Remap for dealing with word wrap
set.gp = "git grep -n"
set.completeopt = { "menuone", "noselect", "noinsert" }
set.shortmess = set.shortmess + { c = true }
set.background = "dark"
set.ignorecase = true -- ignore case in search
set.infercase = true -- adjust case in search
set.smartcase = true -- do not ignore case with capitals
set.scrolloff = 8
set.hlsearch = true
set.updatetime = 300
set.splitright = true -- put new splits to the right
set.splitbelow = true -- put new splits below
set.lazyredraw = true -- do not redraw for macros, faster execution
set.undofile = true -- persistent undo even after session close
set.spellfile = vim.fn.stdpath "config" .. "/spell/en.utf-8.add"
set.formatoptions:remove { "o" }
set.emoji = true

set.number = true
set.encoding = "utf-8"
set.cursorline = true
set.autoread = true

set.expandtab = true
set.shiftwidth = 2
set.softtabstop = 2
set.autoindent = true
set.relativenumber = true
set.incsearch = true
set.inccommand = "split" -- preview of replacement operations
set.laststatus = 2
set.cmdheight = 1

-- Set KUBECONFIG environment variable for homelab access
vim.env.KUBECONFIG = "/home/decoder/dev/homelab/kubeconfig"
