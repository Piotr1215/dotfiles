-- Helper Functions {{{
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local api = vim.api
local sysname = vim.loop.os_uname().sysname

local function map(mode, shortcut, command)
  vim.api.nvim_set_keymap(mode, shortcut, command, { noremap = true, silent = true })
end

local function emap(shortcut, command)
  map('', shortcut, command)
end

--Leader normal mapping
local function lnmap(shortcut, command)
  local leader = "<leader>" .. shortcut
  map('n', leader, command)
end

local function nmap(shortcut, command)
  map('n', shortcut, command)
end

local function imap(shortcut, command)
  map('i', shortcut, command)
end

local function vmap(shortcut, command)
  map('v', shortcut, command)
end

local function xmap(shortcut, command)
  map('x', shortcut, command)
end

local function omap(shortcut, command)
  map('o', shortcut, command)
end

local function smap(shortcut, command)
  map('s', shortcut, command)
end

local function tmap(shortcut, command)
  map('t', shortcut, command)
end

local set = vim.opt
local vcmd = vim.cmd
-- }}}

-- Settings {{{
vcmd('syntax enable')
vcmd('syntax on')
vcmd('filetype on')
vcmd('filetype plugin indent on')
vcmd('set clipboard=unnamedplus')
vcmd('set winbar=%=%m\\ %f')
vcmd('set completefunc=emoji#complete')
vcmd('set statusline+=%#warningmsg#')
vcmd('set statusline+=%{SyntasticStatuslineFlag()}')
vcmd('set statusline+=%*')
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
set.autochdir = true
set.splitright = true -- put new splits to the right
set.splitbelow = true -- put new splits below

set.number = true
set.encoding = "utf-8"
set.cursorline = true

set.expandtab = true
set.shiftwidth = 2
set.softtabstop = 2
set.autoindent = true
set.relativenumber = true
set.incsearch = true
set.laststatus = 3

--cmd('colorscheme PaperColor')
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
require('telescope').setup {
  extensions = {
    fzf = {
      fuzzy = true, -- false will only do exact matching
      override_generic_sorter = true, -- override the generic sorter
      override_file_sorter = true, -- override the file sorter
      case_mode = "smart_case", -- or "ignore_case" or "respect_case"
      -- the default case_mode is "smart_case"
    }
  }
}
vcmd('colorscheme nightfox')
require('lualine').setup()
require("nvim-tree").setup({
  respect_buf_cwd = true,
  update_cwd = true,
  update_focused_file = {
    enable = true,
    update_cwd = true
  },
})

require("vale").setup({
  -- path to the vale binary.
  bin = "/usr/local/bin/vale",
  -- path to your vale-specific configuration.
  vale_config_path = "$HOME/.vale.ini",
})

require("null-ls").setup({
  sources = {
    require("null-ls").builtins.diagnostics.vale,
  },
})
local null_ls = require("null-ls")
local helpers = require("null-ls.helpers")

local uplint = {
  vim.lsp.buf.format({ timeout_ms = 2000 }),
  method = null_ls.methods.DIAGNOSTICS_ON_SAVE,
  filetypes = { "yaml" },
  -- null_ls.generator creates an async source
  -- that spawns the command with the given arguments and options
  generator = null_ls.generator({
    command = "up",
    args = { "xpls", "serve", "--verbose" },
    to_stdin = false,
    from_stderr = true,
    multiple_files = true,
    -- choose an output format (raw, json, or line)
    format = "json",
    to_temp_file = false,
    use_cache = false,
    check_exit_code = function(code, stderr)
      local success = code <= 1

      if not success then
        -- can be noisy for things that run often (e.g. diagnostics), but can
        -- be useful for things that run on demand (e.g. formatting)
        print(stderr)
      end

      return success
    end,
    -- use helpers to parse the output from string matchers,
    -- or parse it manually with a function
    on_output = helpers.diagnostics.from_patterns({
      {
        pattern = [[:(%d+):(%d+) [%w-/]+ (.*)]],
        groups = { "row", "col", "message" },
      },
      {
        pattern = [[:(%d+) [%w-/]+ (.*)]],
        groups = { "row", "message" },
      },
    }),
  }),
}

null_ls.register(uplint)

-- Color name (:help cterm-colors) or ANSI code
-- there are some defaults for image directory and image name, you can change them
vim.g.mdip_imgdir = '_media'
vim.g.mdip_imgname = 'image'
vim.g['plantuml_previewer#viewer_path'] = '~/.vim/bundle/plantuml-previewer.vim/viewer'
vim.g['plantuml_previewer#debug_mode'] = 0
-- setup custom emmet snippets
vim.g.user_emmet_settings = 'webapi#json#decode(join(readfile(expand(\'~/.snippets_custom.json\')), "\n"))'
vim.g.indentLine_char = '⦙'
-- Setup for slime
vim.g.slime_target = "tmux"
vim.g.slime_default_config = '{"socket_name": "default", "target_pane": "{last}"}'
-- setup for netrw
vim.g.netrw_winsize = 30
vim.g.netrw_banner = 0
vim.g.netrw_keepdir = 0
-- setup for markdown snippet
vim.g.vim_markdown_folding_disabled = 0
vim.g.vim_markdown_folding_style_pythonic = 1
vim.g.vim_markdown_folding_level = 2
vim.g.vim_markdown_toc_autofit = 1
vim.g.vim_markdown_conceal = 0
vim.g.vim_markdown_conceal_code_blocks = 0
vim.g.vim_markdown_no_extensions_in_markdown = 1
vim.g.vim_markdown_autowrite = 1
vim.g.vim_markdown_follow_anchor = 1
vim.g.vim_markdown_auto_insert_bullets = 0
vim.g.vim_markdown_new_list_item_indent = 0
-- setup for syntastic
vim.g.syntastic_always_populate_loc_list = 0
vim.g.syntastic_auto_loc_list = 0
vim.g.syntastic_check_on_open = 0
vim.g.syntastic_check_on_wq = 0
vim.g.syntastic_python_checkers = '[\'flake8\']'
-- setup for terraform
vim.g.terraform_fmt_on_save = 1
vim.g.terraform_align = 1
-- setup for ctrlp
vim.g.ctrlp_map = '<c-p>'
vim.g.ctrlp_cmd = 'CtrlPMixed'
vim.g.ctrlp_working_path_mode = 'ra'
vim.g.ctrlp_custom_ignore = '\\v[\\/]\\.(git|hg|svn)$'
vim.g.ctrlp_custom_ignore = {
  dir = { '\\v[\\/]\\.(git|hg|svn)$' },
  file = { '\\v\\.(exe|so|dll)$' },
  link = { 'some_bad_symbolic_links' },
}
-- setup for indent line
vim.g.indentLine_char = '|'
vim.g.go_fmt_command = "goimports"
vim.g.go_highlight_types = 1
vim.g.go_highlight_fields = 1
vim.g.go_highlight_structs = 1
vim.g.go_highlight_interfaces = 1
vim.g.go_highlight_operators = 1
-- MarkdownPreview settings
vim.g.mkdp_browser = '/usr/bin/google-chrome'
vim.g.mkdp_echo_preview_url = 0
-- Nerdcommenter
vim.g.NERDSpaceDelims = 1
-- }}}

-- Plugins {{{
require('packer').startup(function(use)
  -- Packer
  use 'wbthomason/packer.nvim'
  -- Git
  use 'alaviss/nim.nvim'
  use 'airblade/vim-gitgutter'
  use 'cljoly/telescope-repo.nvim'
  use 'kdheepak/lazygit.nvim'
  -- Editor Extensions
  use "stevearc/dressing.nvim"
  use { 'anuvyklack/hydra.nvim',
    requires = 'anuvyklack/keymap-layer.nvim' -- needed only for pink hydras
  }
  use {
    "folke/which-key.nvim",
    config = function()
      require("which-key").setup {
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      }
    end
  }
  use 'vimpostor/vim-tpipeline'
  use 'famiu/nvim-reload'
  use 'easymotion/vim-easymotion'
  use 'ferrine/md-img-paste.vim'
  use 'L3MON4D3/LuaSnip'
  use 'hrsh7th/vim-vsnip'
  use 'hrsh7th/vim-vsnip-integ'
  use 'jpalardy/vim-slime'
  use 'junegunn/fzf.vim'
  use 'nvim-telescope/telescope-symbols.nvim'
  use {
    'kyazdani42/nvim-tree.lua',
    requires = {
      'kyazdani42/nvim-web-devicons', -- optional, for file icon
    },
    tag = 'nightly' -- optional, updated every week. (see issue #1193)
  }
  use {
    'junegunn/fzf',
    run = './install --bin'
  }
  use {
    "folke/zen-mode.nvim",
    config = function()
      require("zen-mode").setup {
      }
    end
  }
  use 'lukas-reineke/indent-blankline.nvim'
  use 'majutsushi/tagbar'
  use 'mattn/emmet-vim'
  use 'mattn/webapi-vim'
  use 'mhinz/vim-startify'
  use {
    'nvim-lualine/lualine.nvim',
    requires = {
      'kyazdani42/nvim-web-devicons',
      'arkav/lualine-lsp-progress',
    },
  }
  -- Programming
  use 'fatih/vim-go'
  -- DevOps
  use 'hashivim/vim-terraform'
  -- Telescope
  use 'christoomey/vim-system-copy'
  use 'ctrlpvim/ctrlp.vim'
  -- Lua
  use {
    "ahmedkhalf/project.nvim",
    config = function()
      require("project_nvim").setup {
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      }
    end
  }
  -- Debugging
  use 'mfussenegger/nvim-dap'
  use 'leoluz/nvim-dap-go'
  use {
    "rcarriga/nvim-dap-ui",
    requires = {
      "mfussenegger/nvim-dap"
    }
  }
  use 'theHamsta/nvim-dap-virtual-text'
  use 'nvim-telescope/telescope-dap.nvim'
  -- Markdown
  use 'renerocksai/telekasten.nvim'
  use 'SidOfc/mkdx'
  use({ "iamcco/markdown-preview.nvim",
    run = "cd app && npm install",
    setup = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    ft = { "markdown" }, })
  use 'dhruvasagar/vim-open-url'
  use 'marcelofern/vale.nvim'
  use 'jose-elias-alvarez/null-ls.nvim'
  use {
    "folke/trouble.nvim",
    requires = "kyazdani42/nvim-web-devicons",
    config = function()
      require("trouble").setup {
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      }
    end
  }
  use 'dhruvasagar/vim-table-mode'
  use 'godlygeek/tabular'
  use 'plasticboy/vim-markdown'
  -- Look & Feel
  use 'EdenEast/nightfox.nvim'
  use 'NLKNguyen/papercolor-theme'
  -- LSP Autocomplete
  use {
    'hrsh7th/cmp-vsnip',
    requires = {
      'hrsh7th/vim-vsnip',
      'rafamadriz/friendly-snippets',
    }
  }
  use {
    'hrsh7th/nvim-cmp',
    requires = {
      'nvim-treesitter',
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-cmdline',
    }
  }
  use { 'mhartington/formatter.nvim' }
  use { 'neoclide/coc.nvim', branch = 'release' }
  use {
    'nvim-telescope/telescope-file-browser.nvim'
  }
  use {
    'nvim-telescope/telescope-fzf-native.nvim', run = 'make'
  }
  use {
    'nvim-telescope/telescope.nvim',
    requires = {
      { 'nvim-lua/popup.nvim' },
      { 'nvim-lua/plenary.nvim' }
    }
  }
  use 'onsails/lspkind-nvim'
  use 'preservim/nerdcommenter'
  use 'Raimondi/delimitMate'
  use 'rhysd/vim-clang-format'
  use 'ryanoasis/vim-devicons'
  use 'sakshamgupta05/vim-todo-highlight'
  use 'sheerun/vim-polyglot'
  use { 'tami5/lspsaga.nvim', requires = { 'neovim/nvim-lspconfig' } }
  use 'tpope/vim-fugitive'
  use 'tpope/vim-surround'
  use 'tyru/open-browser.vim'
  use 'vim-syntastic/syntastic'
  use 'voldikss/vim-floaterm'
  use 'weirongxu/plantuml-previewer.vim'
  use 'wellle/targets.vim'
  use { 'williamboman/nvim-lsp-installer', { 'neovim/nvim-lspconfig', } }
  use 'Yggdroot/indentLine'
  use { "ellisonleao/glow.nvim", branch = 'main' }
  use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }
end)
--- }}}

-- Autocommands {{{
local indentSettings = vim.api.nvim_create_augroup("IndentSettings", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  command = "setlocal expandtab shiftwidth=2 softtabstop=2 cindent",
  group = indentSettings,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "yaml" },
  command = "setlocal ts=2 sts=2 sw=2 expandtab",
  group = indentSettings,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "python" },
  command = "setlocal expandtab shiftwidth=4 softtabstop=4 autoindent",
  group = indentSettings,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "go" },
  command = "set foldmethod=manual",
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "go" },
  command = "nmap <buffer><silent> <leader>fld :%g/ {/normal! zf%<CR>",
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown" },
  command = "nmap <buffer><silent> <leader>p :call mdip#MarkdownClipboardImage()<CR>",
})

api.nvim_exec(
  [[
    augroup fileTypes
     autocmd FileType lua setlocal foldmethod=marker
     autocmd FileType go setlocal foldmethod=expr
     autocmd BufRead,BufNewFile .envrc set filetype=sh
    augroup end
  ]], false
)

api.nvim_exec(
  [[
    augroup helpers
     autocmd!
     autocmd TermOpen term://* startinsert
     autocmd BufEnter * silent! lcd %:p:h
    augroup end
  ]], false
)

api.nvim_exec(
  [[
    augroup plantuml
     autocmd BufWritePost *.puml silent! !java -DPLANTUML_LIMIT_SIZE=8192 -jar /usr/local/bin/plantuml.jar -tsvg <afile> -o ./rendered
    augroup end
  ]], false
)

api.nvim_exec(
  [[
    augroup autoformat_settings
     autocmd FileType c,cpp,proto,javascript setlocal equalprg=clang-format
     autocmd FileType python AutoFormatBuffer yapf
    augroup end
  ]], false
)

api.nvim_exec(
  [[
    augroup last_cursor_position
     autocmd!
     autocmd BufReadPost *
       \ if line("'\"") > 1 && line("'\"") <= line("$") && &ft !~# 'commit' | execute "normal! g`\"zvzz" | endif
    augroup end
  ]], false
)
-- Compile packages on add
vim.cmd
[[
    augroup Packer
     autocmd!
     autocmd BufWritePost plugins.lua source <afile> | PackerSync
    augroup end
  ]]

vim.cmd
[[
 augroup MKDX
   au!
   au FileType markdown so $HOME/.vim/bundle/mkdx/ftplugin/markdown.vim
 augroup END
]]
if sysname == 'Darwin' then
  api.nvim_exec(
    [[
         augroup plant_folder
          autocmd FileType plantuml let g:plantuml_previewer#plantuml_jar_path = get(
              \  matchlist(system('cat `which plantuml` | grep plantuml.jar'), '\v.*\s[''"]?(\S+plantuml\.jar).*'),
              \  1,
              \  0
              \)
         augroup end
       ]], false)
end
require('telescope').setup {
  --  defaults   = {},
  --  pickers    = {},
  extensions = {
    file_browser = {}
  }
}
-- }}}

-- Telescope {{{
require('telescope').load_extension('file_browser')
require('telescope').load_extension('repo')
require('telescope').load_extension('fzf')
require('telescope').load_extension('projects')
local key = vim.api.nvim_set_keymap
local set_up_telescope = function()
  local set_keymap = function(mode, bind, cmd)
    key(mode, bind, cmd, { noremap = true, silent = true })
  end
  set_keymap('n', '<leader><leader>', [[<cmd>lua require('telescope.builtin').buffers()<CR>]])
  --set_keymap('n', '<leader>tf', [[<cmd>lua require('telescope.builtin').find_files({find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<CR>]])
  set_keymap('n', '<leader>fp', [[<cmd>lua require('telescope.builtin').find_files({search_dirs = {"~/dev"}})<CR>]])
  set_keymap('n', '<leader>fr', [[<cmd>lua require'telescope'.extensions.repo.list{search_dirs = {"~/dev"}}<CR>]])
  set_keymap('n', '<leader>fgr', [[<cmd>lua require('telescope.builtin').live_grep()<CR>]])
  set_keymap('n', '<leader>fg', [[<cmd>lua require('telescope.builtin').git_files()<CR>]])
  set_keymap('n', '<leader>fo', [[<cmd>lua require('telescope.builtin').oldfiles()<CR>]])
  set_keymap('n', '<leader>fi', ':Telescope file_browser<CR>')
  set_keymap('n', '<leader>fst', [[<cmd>lua require('telescope.builtin').grep_string({search_dirs = {"~/dev"}})<CR>]])
  set_keymap('n', '<leader>fb', [[<cmd>lua require('telescope.builtin').current_buffer_fuzzy_find()<CR>]])
  set_keymap('n', '<leader>fh', [[<cmd>lua require('telescope.builtin').help_tags()<CR>]])
  set_keymap('n', '<leader>ft', [[<cmd>lua require('telescope.builtin').tagstack()<CR>]])
  set_keymap('n', '<leader>re', [[<cmd>lua require('telescope.builtin').registers()<CR>]])
  set_keymap('n', '<leader>fT', [[<cmd>lua require('telescope.builtin').tags{ only_current_buffer = true }<CR>]])
  -- set_keymap('n', '<leader>sf', [[<cmd>lua vim.lsp.buf.formatting()<CR>]])
end

set_up_telescope()

lnmap("tkf", ":lua require('telekasten').find_notes()<CR>") -- Move Line Up in Normal Mode
-- }}}

-- User commands {{{
-- Format with default CocAction
vim.api.nvim_create_user_command(
  'Format',
  "call CocAction('format')",
  { bang = true }
)

--Open Buildin terminal vertical mode
vim.api.nvim_create_user_command(
  'VT',
  "vsplit | lcd %:p:h | terminal",
  { bang = false, nargs = '*' }
)

--Open Buildin terminal
vim.api.nvim_create_user_command(
  'T',
  "split | lcd %:h | resize 15 | terminal",
  { bang = true, nargs = '*' }
)

--Execute shell command in a read-only scratchpad buffer
vim.api.nvim_create_user_command(
  'R',
  "new | setlocal buftype=nofile bufhidden=hide noswapfile | r !<args>",
  { bang = false, nargs = '*', complete = 'shellcmd' }
)

--Get diff for current file
vim.api.nvim_create_user_command(
  'Gdiff',
  "execute  'w !git diff --no-index -- % -'",
  { bang = false }
)

--Get diff for current file
vim.api.nvim_create_user_command(
  'Pretty',
  "CocCommand prettier.formatFile",
  { bang = true }
)
nmap("<C-f>", ":Pretty<CR>")

vim.cmd [[
function! WinMove(key)
   let t:curwin = winnr()
   exec "wincmd ".a:key
   if (t:curwin == winnr())
       if (match(a:key,'[jk]'))
           wincmd v
       else
           wincmd s
       endif
       exec "wincmd ".a:key
   endif
endfunction
]]
-- }}}

-- Hydra {{{
local Hydra = require("hydra")

Hydra({
  name = "Change / Resize Window",
  mode = { "n" },
  body = "<C-w>",
  config = {
    -- color = "pink",
  },
  heads = {
    -- move between windows
    { "<C-h>", "<C-w>h" },
    { "<C-j>", "<C-w>j" },
    { "<C-k>", "<C-w>k" },
    { "<C-l>", "<C-w>l" },

    -- resizing window
    { "H", "<C-w>3<" },
    { "L", "<C-w>3>" },
    { "K", "<C-w>2+" },
    { "J", "<C-w>2-" },

    -- equalize window sizes
    { "e", "<C-w>=" },

    -- close active window
    { "Q", ":q<cr>" },
    { "<C-q>", ":q<cr>" },

    -- exit this Hydra
    { "q", nil, { exit = true, nowait = true } },
    { ";", nil, { exit = true, nowait = true } },
    { "<Esc>", nil, { exit = true, nowait = true } },
  },
})

-- }}}

-- Mappings {{{
-- Map only if Linux
vim.api.nvim_set_keymap('n', 'k', "v:count == 0 ? 'gk' : 'k'", { noremap = true, expr = true, silent = true })
vim.api.nvim_set_keymap('n', 'j', "v:count == 0 ? 'gj' : 'j'", { noremap = true, expr = true, silent = true })
vim.keymap.set("n", "<C-j>", [[:keepjumps normal! j}k<cr>]], { noremap = true, silent = true })
vim.keymap.set("n", "<C-k>", [[:keepjumps normal! k{j<cr>]], { noremap = true, silent = true })
local opts = { noremap = true, silent = true }
vim.keymap.set("n", "<Leader><Leader>i", "<cmd>PickIcons<cr>", opts)
vim.keymap.set("n", "<Leader>ts", "<cmd>Telescope<cr>", opts)
vim.keymap.set("i", "<C-9>", "]", opts)
vim.keymap.set("i", "<C-8>", "[", opts)
vim.keymap.set("n", "<C-9>", "]", opts)
vim.keymap.set("n", "<C-8>", "[", opts)
vim.keymap.set("i", "<C-i>", "<cmd>PickIconsInsert<cr>", opts)
vim.keymap.set("i", "<A-i>", "<cmd>PickAltFontAndSymbolsInsert<cr>", opts)
if sysname == 'Linux' then
  nmap('ö', '/')
  imap('ö', '/')
end
-- MOVE AROUND --
vmap("<S-PageDown>", ":m '>+1<CR>gv=gv") -- Move Line Down in Visual Mode
vmap("<S-PageUp>", ":m '<-2<CR>gv=gv") -- Move Line Up in Visual Mode
nmap("<leader>k", ":m .-2<CR>==") -- Move Line Up in Normal Mode
nmap("<leader>j", ":m .+1<CR>==") -- Move Line Down in Normal Mode
nmap("<Leader>nh", ":.,/^#/<CR>") -- Got to next markdown header
nmap("<Leader>em", ":/\\V\\c\\<\\>") -- find exact match

-- SEARCH & REPLACE --
-- Easy Motion Mappings
emap("<Leader>o", "<Plug>(easymotion-prefix)")
emap("<Leader>of", "<Plug>(easymotion-bd-f)")
emap("<Leader>ol", "<Plug>(easymotion-bd-w)")
emap("<Leader>oo", "<Plug>(easymotion-overwin-f2)")
-- Stop search highlight
nmap(",<space>", ":nohlsearch<CR>")
vmap("<C-r>", '"hy:%s/<C-r>h//gc<left><left><left>')
vmap("//", 'y/\\V<C-R>=escape(@",\'/\')<CR><CR>')

-- MACROS --
nmap("<Leader>q", "@q")
xmap("Q", ":'<,'>:normal @q<CR>")
lnmap("jq", ":g/{/.!jq .<CR>")
tmap("<ESC>", "<C-\\><C-n>")

-- MANIPULATE TEXT --
-- Copy file name
lnmap("cpf", ":let @* = expand(\"%:t\")<CR>")
-- Comment paragraphs
nmap("<silent> <leader>c}", "V}:call NERDComment('x', 'toggle')<CR>")
nmap("<silent> <leader>c{", "V{:call NERDComment('x', 'toggle')<CR>")
-- Insert 2 empty lines and go into inser mode
nmap("<leader>fe", "<Plug>(grammaruos-fixit)")
nmap("<leader>fa", "<Plug>(grammaruos-fixall)")
nmap("<leader>L", "O<ESC>O")
nmap("<leader>l", "o<cr>")
-- Select last pasted text
nmap("gp", "`[v`]")
-- Add line below without entering insert mode!
nmap("<leader><Up>", ':<c-u>put!=repeat([\'\'],v:count)<bar>\']+1<cr>')
nmap("<leader><Down>", ':<c-u>put =repeat([\'\'],v:count)<bar>\'[-1<cr>')
-- Paste crom clipboard
nmap("<leader>2", '"*p')
-- Copy selection to clipboard with Ctrl+c
vmap("<C-c>", '"*y')
-- Copy word under cusror to the clipboard buffer
nmap('<leader>yw', '"*yiw')
-- Removes whitespace
nmap('<Leader>rspace', ':%s/\\s\\+$//e')
-- Removes empty lines if there are more than 2
nmap('<Leader>rlines', ':%s/\\n\\{3,}/\\r\\r/e')
-- Insert space
nmap('<Leader>i', 'i<space><esc>')
-- delete word forward in insert mode
imap('<C-e>', '<C-o>dw<Left>')
-- delete word with Ctrl Backspace
imap('<C-BS>', '<C-W>')
-- Copies till the end of a line. Fits with Shift + D, C etc
nmap('Y', 'yg_')
-- Replace multiple words simultaniously
-- Repeat, with .
nmap('<Leader>x', '*``cgn')
nmap('<Leader>X', '#``cgN')
-- Copy from cursor to end of line
nmap('<leader>y', '"+y$')
-- cut and copy content to next header #
nmap('cO', ':.,/^#/-1d<CR>')
nmap('cY', ':.,/^#/-1y<CR>')
-- Split line in two
nmap('<Leader>sp', 'i<CR><Esc>')
-- Copy function or routine body and keyword
nmap('yaf', '[m{jV]m%y')
nmap('<leader>wi', ':setlocal textwidth=80<cr>')
vim.cmd(
  [[
     function! s:check_back_space() abort
       let col = col('.') - 1
       return !col || getline('.')[col - 1]  =~# '\s'
     endfunction
     ]])

-- MARKDOWN --
-- Operations on Code Block
vim.cmd(
  [[
     function! MarkdownCodeBlock(outside)
         call search('```', 'cb')
         if a:outside
             normal! Vo
         else
             normal! j0Vo
         endif
         call search('```')
         if ! a:outside
             normal! k
         endif
     endfunction
     ]])
omap('am', ':call MarkdownCodeBlock(1)<cr>')
xmap('am', ':call MarkdownCodeBlock(1)<cr>')
omap('im', ':call MarkdownCodeBlock(0)<cr>')
xmap('im', ':call MarkdownCodeBlock(0)<cr>')
-- Markdown Previev
nmap('<leader>mp', ':MarkdownPreview<CR>')
-- Fix Markdown Errors
nmap('<leader>fx', ':<C-u>CocCommand markdownlint.fixAll<CR>')
--" Markdown paste image

-- EXTERNAL --
-- Execute line under cursor in shell
nmap('<leader>ex', ':exec \'!\'.getline(\'.\')<CR>')
-- Set spellcheck on/off
nmap('<Leader>son', ':setlocal spell spelllang=en_us<CR>')
nmap('<Leader>sof', ':set nospell<CR>')
-- Accept first grammar correction
nmap('<Leader>c', '1z=')
-- Upload selected to ix.io
vmap('<Leader>pp', ':w !curl -F "f:1=<--- ix.io<CR>')
-- Execute Command in scratchpad buffer
nmap('<leader>sr', '<Plug>SendRight<cr>')
xmap('<silent>srv', '<Plug>SendRightV<cr>')
nmap('<leader>sd', '<Plug>SendDown<cr>')
xmap('<silent>sdv', '<Plug>SendDownV<cr>')
-- setup mapping to call :LazyGit
nmap('<leader>gg', ':LazyGit<CR>')
-- NAVIGATION --
-- Nvim Tree settings
nmap('<leader>dd', ':NvimTreeToggle<CR>')
nmap('<Leader>da', ':NvimTreeFindFile<CR>')
-- Save buffer
nmap('<leader>w', ':w<CR>')
-- Move screen to contain current line at the top
--local pathToVimInit = ':source ' .. vim.fn.expand('~/.config/nvim/init.vim<CR>')
nmap('<leader>sv', ':source /home/decoder/.config/nvim/init.vim<CR>')
--nmap('<leader>sv', pathToVimInit)
-- jj in insert mode instead of ESC
imap('jj', '<Esc>')
imap('jk', '<Esc>')
-- Zoom split windows
nmap('Zz', '<c-w>_ | <c-w>|')
nmap('Zo', '<c-w>=')
-- Floatterm settings
nmap('<Leader>fs', ':FloatermShow<CR>')
nmap('<Leader>fh', ':FloatermHide<CR>')
nmap('<Leader>fn', ':FloatermNext<CR>')
nmap('<Leader>fc', ':FloatermKill<CR>')

-- PROGRAMMING --
-- Use `[g` and `]g` to navigate diagnostics
-- Apply AutoFix to problem on the current line.
-- Map function and class text objects
-- NOTE: Requires 'textDocument.documentSymbol' support from the language server.
xmap('if', '<Plug>(coc-funcobj-i)')
omap('if', '<Plug>(coc-funcobj-i)')
xmap('af', '<Plug>(coc-funcobj-a)')
omap('af', '<Plug>(coc-funcobj-a)')
-- Use CTRL-S for selections ranges.
-- Requires 'textDocument/selectionRange' support of language server.
nmap('<silent>', '<C-s> <Plug>(coc-range-select)')
xmap('<silent>', '<C-s> <Plug>(coc-range-select)')
-- vsnip settings
-- Expand
imap('<expr>', '<C-j>   vsnip#expandable()  ? \'<Plug>(vsnip-expand)\'         : \'<C-j>')
smap('<expr>', '<C-j>   vsnip#expandable()  ? \'<Plug>(vsnip-expand)\'         : \'<C-j>')

-- Expand or jump
imap('<expr>', '<C-l>   vsnip#available(1)  ? \'<Plug>(vsnip-expand-or-jump)\' : \'<C-l>')
smap('<expr>', '<C-l>   vsnip#available(1)  ? \'<Plug>(vsnip-expand-or-jump)\' : \'<C-l>')
-- Select or cut text to use as $TM_SELECTED_TEXT in the next snippet.
-- See https://github.com/hrsh7th/vim-vsnip/pull/50
nmap('<leader>t', '<Plug>(vsnip-select-text)')
xmap('<leader>t', '<Plug>(vsnip-select-text)')
nmap('<leader>tc', '<Plug>(vsnip-cut-text)')
xmap('<leader>tc', '<Plug>(vsnip-cut-text)')

-- Abbreviations
vim.cmd('abb cros Crossplane')

-- Telekasten
nmap('<leader>tk', ':lua require(\'telekasten\').panel()<CR>')
-- }}}

-- LSP {{{
require('lspconfig')
local lsp_installer = require("nvim-lsp-installer")

local servers = {
  "bashls",
  "sumneko_lua",
  "dockerls",
  "gopls",
  "html",
  "vimls",
  "yamlls",
  "awk_ls",
  "emmet_ls",
}

for _, name in pairs(servers) do
  local server_is_found, server = lsp_installer.get_server(name)
  if server_is_found and not server:is_installed() then
    print("Installing " .. name)
    server:install()
  end
end

local on_attach = function(_, bufnr)
  -- Create some shortcut functions.
  -- NOTE: The `vim` variable is supplied by Neovim.
  local function buf_set_keymap(...)
    vim.api.nvim_buf_set_keymap(bufnr, ...)
  end

  local function buf_set_option(...)
    vim.api.nvim_buf_set_option(bufnr, ...)
  end

  -- Enable completion triggered by <c-x><c-o>
  buf_set_option('omnifunc', 'v:lua.vim.lsp.omnifunc')

  local options = { noremap = true, silent = true }

  -- ======================= The Keymaps =========================
  -- jump to definition
  buf_set_keymap('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<CR>', options)

  -- Format buffer
  buf_set_keymap('n', '<c-f>', '<cmd>lua vim.lsp.buf.format({ async = true })<CR>', options)
  buf_set_keymap('n', 'dm', '<cmd>lua vim.lsp.buf.document_symbol()<CR>', options)

  -- Jump LSP diagnostics
  -- NOTE: Currently, there is a bug in lspsaga.diagnostic module. Thus we use
  --       Vim commands to move through diagnostics.
  buf_set_keymap('n', '[g', ':Lspsaga diagnostic_jump_prev<CR>', options)
  buf_set_keymap('n', ']g', ':Lspsaga diagnostic_jump_next<CR>', options)

  -- Rename symbol
  buf_set_keymap('n', '<leader>rn', "<cmd>lua require('lspsaga.rename').rename()<CR>", options)

  -- Find references
  buf_set_keymap('n', 'gr', '<cmd>lua require("lspsaga.provider").lsp_finder()<CR>', options)

  -- Doc popup scrolling
  buf_set_keymap('n', 'K', "<cmd>lua require('lspsaga.hover').render_hover_doc()<CR>", options)

  -- codeaction
  buf_set_keymap('n', '<leader>ac', "<cmd>lua require('lspsaga.codeaction').code_action()<CR>", options)
  buf_set_keymap('v', '<leader>a', ":<C-U>lua require('lspsaga.codeaction').range_code_action()<CR>", options)

  -- Floating terminal
  -- NOTE: Use `vim.cmd` since `buf_set_keymap` is not working with `tnoremap...`
  vim.cmd [[
  nnoremap <silent> <A-d> <cmd>lua require('lspsaga.floaterm').open_float_terminal()<CR>
  tnoremap <silent> <A-d> <C-\><C-n>:lua require('lspsaga.floaterm').close_float_terminal()<CR>
  ]]
end

local server_specific_opts = {
  sumneko_lua = function(options)
    options.settings = {
      Lua = {
        -- NOTE: This is required for expansion of lua function signatures!
        completion = { callSnippet = "Replace" },
        diagnostics = {
          globals = { 'vim' },
        },
      },
    }
  end,

  html = function(options)
    options.filetypes = { "html", "htmldjango" }
  end,
}

-- `nvim-cmp` comes with additional capabilities, alongside the ones
-- provided by Neovim!
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').update_capabilities(capabilities)

lsp_installer.on_server_ready(function(server)
  -- the keymaps, flags and capabilities that will be sent to the server as
  -- options.
  local opts = {
    on_attach = on_attach,
    flags = { debounce_text_changes = 150 },
    capabilities = capabilities,
  }

  -- If the current surver's name matches with the ones specified in the
  -- `server_specific_opts`, set the options.
  if server_specific_opts[server.name] then
    server_specific_opts[server.name](opts)
  end

  -- And set up the server with our configuration!
  server:setup(opts)
end)

-- nvim-cmp
local lspkind = require('lspkind')
local cmp = require("cmp")

local has_words_before = function()
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

local feedkey = function(key, mode)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), mode, true)
end

local cmp_kinds = {
  Text = "",
  Method = "",
  Function = "",
  Constructor = "",
  Field = "ﰠ",
  Variable = "",
  Class = "ﴯ",
  Interface = "",
  Module = "",
  Property = "ﰠ",
  Unit = "塞",
  Value = "",
  Enum = "",
  Keyword = "",
  Snippet = "",
  Color = "",
  File = "",
  Reference = "",
  Folder = "",
  EnumMember = "",
  Constant = "",
  Struct = "פּ",
  Event = "",
  Operator = "",
  TypeParameter = "",
}

cmp.setup({
  snippet = {
    expand = function(args)
      vim.fn["vsnip#anonymous"](args.body)
    end,
  },

  formatting = {
    format = lspkind.cmp_format({
      preset = 'codicons',
      symbol_map = cmp_kinds, -- The glyphs will be used by `lspkind`
      async = true,
      menu = ({
        buffer = "[Buffer]",
        nvim_lsp = "[LSP]",
        luasnip = "[LuaSnip]",
        nvim_lua = "[Lua]",
        latex_symbols = "[Latex]",
      }),
    }),
  },

  mapping = {
    ['<C-p>'] = cmp.mapping.select_prev_item(),
    ['<C-n>'] = cmp.mapping.select_next_item(),
    ['<C-d>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<C-e>'] = cmp.mapping.close(),
    ['<CR>'] = cmp.mapping.confirm {
      behavior = cmp.ConfirmBehavior.Replace,
      select = true,
    },

    -- Use Ctrl + j and Shift-Ctrl + j to browse through the suggestions.
    ["<Tab>"] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      elseif vim.fn["vsnip#available"](1) == 1 then
        feedkey("<Plug>(vsnip-expand-or-jump)", "")
      elseif has_words_before() then
        cmp.complete()
      else
        fallback()
      end
    end, { "i", "s" }),

    ["<S-Tab>"] = cmp.mapping(function()
      if cmp.visible() then
        cmp.select_prev_item()
      elseif vim.fn["vsnip#jumpable"](-1) == 1 then
        feedkey("<Plug>(vsnip-jump-prev)", "")
      end
    end, { "i", "s" }),
  },

  sources = {
    { name = 'nvim_lsp' },
    { name = 'nvim_lua' },
    { name = 'vsnip' },
    { name = 'buffer' },
    { name = 'emoji' },
    { name = 'path' },
  },
})

-- Use buffer source for `/`
cmp.setup.cmdline('/', {
  sources = {
    { name = 'buffer' }
  }
})

-- Use cmdline & path source for ':'
cmp.setup.cmdline(':', {
  sources = cmp.config.sources({
    { name = 'path' }
  }, {
    { name = 'cmdline' }
  })
})

-- Lualine
require("lualine").setup({
  sections = {
    lualine_c = {
      { "filename", path = 1 },
      "lsp_progress",
    },
  },
})

-- indent-blankline
require("indent_blankline").setup({
  -- for example, context is off by default, use this to turn it on
  space_char_blankline = " ",
  show_current_context = true,
  show_current_context_start = true,
  filetype_exclude = { "help", "packer" },
  buftype_exclude = { "terminal", "nofile" },
  show_trailing_blankline_indent = false,
})

-- treesitter
require("nvim-treesitter.configs").setup({
  ensure_installed = {
    "c",
    "cpp",
    "bash",
    "go",
    "html",
    "yaml",
    "toml",
  },
  highlight = {
    enable = true,
  },
})

local dap, dapui = require("dap"), require("dapui")
require('nvim-dap-virtual-text').setup()
require('dap-go').setup()
dap.listeners.after.event_initialized["dapui_config"] = function()
  dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"] = function()
  dapui.close()
end
dap.listeners.before.event_exited["dapui_config"] = function()
  dapui.close()
end
dap.configurations.go = {
  {
    type = 'go';
    name = 'Debug';
    request = 'launch';
    showLog = false;
    program = "${file}";
    dlvToolPath = vim.fn.exepath('~/go/bin/dlv') -- Adjust to where delve is installed
  },
}
-- load snippets from path/of/your/nvim/config/my-cool-snippets
require("luasnip.loaders.from_vscode").lazy_load()
--- up xpls
--require("lspconfig").up.setup{
--args = {"xpls serve --verbose"},
--filetype = 'yaml'
--}
-- }}}
