-- Settings for plugins
require("mason").setup()

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

require('mini.ai').setup()

require('femaco').setup({
  -- what to do after opening the float
  post_open_float = function(winnr)
    if vim.bo.filetype == "rust" then
      require('rust-tools.standalone').start_standalone_client()
    end
  end
})

require("nvim-tree").setup({
  respect_buf_cwd = true,
  update_cwd = true,
  update_focused_file = {
    enable = true,
    update_cwd = true
  },
})

local prettier = require("prettier")

require("which-key").setup({
  plugins = {
    marks = true, -- shows a list of your marks on ' and `
    registers = true, -- shows your registers on " in NORMAL or <C-r> in INSERT mode
    spelling = {
      enabled = true, -- enabling this will show WhichKey when pressing z= to select spelling suggestions
      suggestions = 20, -- how many suggestions should be shown in the list?
    },
  }
})

prettier.setup({
  bin = 'prettier', -- or `'prettierd'` (v0.22+)
  filetypes = {
    "css",
    "html",
    "javascript",
    "javascriptreact",
    "json",
    "less",
    "markdown",
    "typescript",
    "typescriptreact",
    "yaml",
    "go",
  },
})

require("nvim-surround").setup({
  keymaps = {
    insert = "<C-g>s",
    insert_line = "<C-g>S",
    normal = "ys",
    normal_cur = "yss",
    normal_line = "yS",
    normal_cur_line = "ySS",
    visual = "S",
    visual_line = "gS",
    delete = "d;",
    change = "c;",
  },
})

require('leap').add_default_mappings()

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
  { 'Edit Aliases', 'e ~/.zsh_aliases' },
  { 'Edit Functions', 'e ~/.zsh_functions' },
  { 'Search Dev:   SPC fd', 'Telescope find_files search_dirs=~/dev,--hidden,--with-filename' },
  { 'Search Repos: SPC fr', 'lua require\'telescope\'.extensions.repo.list{search_dirs = {"~/dev"}}' },
  { 'Ranger:       ALT o', 'RnvimrToggle' },
  { 'Change Color: SPC fc', 'Telescope colorscheme' },
  { 'Pick Emoji:   SPC fm', 'Telescope emoji' }
}
vim.g.startify_bookmarks = {
  '~/.config/nvim/lua',
  '~/.zshrc',
  '~/.tmux.conf',
  '~/.config/task/.taskrc',
  '~/.config/ranger/rc.conf',
  '~/scripts/shortcuts.txt',
  '/home/decoder/snap/cheat/common/.config/cheat/conf.yml',
}
vim.g.startify_custom_header = "startify#pad(split(system('fortune -s | cowsay | lolcat; date'), '\n'))"
