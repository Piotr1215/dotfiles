local set = vim.opt
local cmd = vim.cmd

cmd('syntax enable')
cmd('syntax on')
cmd('filetype on')
cmd('filetype plugin indent on')
cmd('set winbar=%=%m\\ %f')
cmd('set completefunc=emoji#complete')
cmd('set statusline+=%#warningmsg#')
cmd('set statusline+=%{SyntasticStatuslineFlag()}')
cmd('set statusline+=%*')
cmd('set wildignore+=*/tmp/*,*.so,*.swp,*.zip')
cmd('set backspace=indent,eol,start')

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

set.mouse = v
set.number = true
set.encoding = "utf-8"
set.cursorline = true
set.clipboard = 'unnamedplus'

set.expandtab = true
set.shiftwidth = 5
set.softtabstop = 4
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
cmd('colorscheme nightfox')
require('lualine').setup()
require('litee.lib').setup()
require('litee.gh').setup()
require('nvim-tree').setup {
     auto_close = true
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
-- Setup for slime
vim.g.slime_target = "tmux"
vim.g.slime_default_config = '{"socket_name": "default", "target_pane": "{last}"}'
-- setup for netrw
vim.g.netrw_winsize = 30
vim.g.netrw_banner = 0
vim.g.netrw_keepdir = 0
-- setup for markdown snippet
vim.g.vim_markdown_folding_disabled = 1
vim.g.vim_markdown_folding_level = 3
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
