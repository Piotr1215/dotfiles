local set = vim.opt
local vcmd = vim.cmd

vcmd('syntax on')
vcmd('syntax enable')
vcmd('filetype on')
vcmd('filetype plugin indent on')
vcmd('set clipboard=unnamedplus')
vcmd('set winbar=%=%m\\ %f')
vcmd('set completefunc=emoji#complete')
-- vcmd('set statusline+=%#warningmsg#')
-- vcmd('set statusline+=%{SyntasticStatuslineFlag()}')
-- vcmd('set statusline+=%*')
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

require 'mdeval'.setup({
  -- Don't ask before executing code blocks
  require_confirmation = false,
  -- Change code blocks evaluation options.
  eval_options = {
    -- Set custom configuration for C++
    cpp = {
      command = { "clang++", "-std=c++20", "-O0" },
      default_header = [[
    #include <iostream>
    #include <vector>
    using namespace std;
      ]]
    },
  },
})

require("catppuccin").setup({
  transparent_background = true,
  term_colors = true,
})

require("tokyonight").setup({
  style = "night", -- The theme comes in three styles, `storm`, a darker variant `night` and `day`
  transparent = true, -- Enable this to disable setting the background color
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
require("mason").setup()
vcmd('colorscheme nightfox')

require("nvim-tree").setup({
  respect_buf_cwd = true,
  update_cwd = true,
  update_focused_file = {
    enable = true,
    update_cwd = true
  },
})

require("telekasten").setup {
  home = "/home/decoder/zettelkasten",
  dailies = "/home/decoder/zettelkasten/daily",
  weeklies = "/home/decoder/zettelkasten/weekly",
  templates = "/home/decoder/zettelkasten/templates",
  -- markdown file extension
  extension = ".md",

  -- following a link to a non-existing note will create it
  follow_creates_nonexisting = true,
  dailies_create_nonexisting = true,
  weeklies_create_nonexisting = true,
}

-- Color name (:help cterm-colors) or ANSI code
-- there are some defaults for image directory and image name, you can change them
vim.g.mdip_imgdir = '_media'
vim.g.mdip_imgname = 'image'
vim.g['plantuml_previewer#viewer_path'] = '~/.vim/bundle/plantuml-previewer.vim/viewer'
vim.g['plantuml_previewer#debug_mode'] = 0
-- setup custom emmet snippets
vim.g.user_emmet_settings = 'webapi#json#decode(join(readfile(expand(\'~/.snippets_custom.json\')), "\n"))'
vim.g.indentLine_char = '⦙'
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
vim.cmd [[
let g:PaperColor_Theme_Options = {
  \   'theme': {
  \     'default.dark': {
  \       'transparent_background': 1
  \     }
  \   }
  \ }
]]
-- setup for indent line
vim.g.indentLine_char = '|'
vim.g.go_fmt_command = "goimports"
vim.g.go_highlight_types = 1
vim.g.go_highlight_fields = 1
vim.g.go_highlight_structs = 1
vim.g.go_highlight_interfaces = 1
vim.g.go_highlight_operators = 1
vim.g.go_fmt_experimental = 1
-- Nerdcommenter
vim.g.NERDSpaceDelims = 1
-- Ranger
vim.g.rnvimr_enable_picker = 1
-- Startify
vim.g.startify_change_to_dir = 1
vim.g.startify_session_persistence = 1
vim.g.startify_change_to_vsc_root = 1
vim.g.startify_session_number = 5
vim.g.startify_files_number = 10
vim.g.startify_session_delete_buffers = 0
vim.g.startify_commands = {
  { 'Help Features', 'h nvim-features' },
  { 'Help Quickref', 'h quickref' },
  { 'Search Dev:   SPC fd', 'Telescope find_files search_dirs=~/dev,--hidden,--with-filename' },
  { 'Search Repos: SPC fr', 'lua require\'telescope\'.extensions.repo.list{search_dirs = {"~/dev"}}' },
  { 'Ranger:       ALT o', 'RnvimrToggle' },
  { 'Change Color: SPC fc', 'Telescope colorscheme' }
}
vim.g.startify_bookmarks = {
  '~/.config/nvim/lua',
  '~/.zshrc',
  '~/.tmux.conf',
  '~/.taskrc',
  '~/.config/ranger/rc.conf',
  '~/scripts/shortcuts.txt',
}
vim.g.startify_custom_header = "startify#pad(split(system('fortune -s | cowsay | lolcat; date'), '\n'))"
