-- Settings for plugins
require("mason").setup()

require("yanksearch").setup {
  lines_above = 0,
  lines_below = 0,
  lines_around = 0, -- This will override lines_above and lines_below if set to a non-zero value
}

require("mini.align").setup()

require("go").setup()
require("dap-python").setup "~/.virtualenvs/debugpy/bin/python"

require("goto-preview").setup {}

require("mdeval").setup {
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
      ]],
    },
  },
}

require("no-neck-pain").setup {
  width = 75,
  buffers = {
    colors = {
      background = "tokyonight-moon",
    },
    right = {
      enabled = false,
    },
  },
}

require("oil").setup {
  view_options = {
    -- Show files and directories that start with "."
    show_hidden = true,
  },
}
require("obsidian").setup {
  dir = "/home/decoder/dev/obsidian/decoder",
  disable_frontmatter = false,
  open_app_foreground = true,
  notes_subdir = "Notes",
  templates = {
    subdir = "Templates",
    date_format = "%Y-%m-%d-%a",
    time_format = "%H:%M",
  },
  finder = "fzf-lua",
  mappings = {
    ["gf"] = require("obsidian.mapping").gf_passthrough(),
  },
  completion = {
    nvim_cmp = true, -- if using nvim-cmp, otherwise set to false
    prepend_note_id = false,
  },
  note_id_func = function(title)
    -- Create note IDs in a Zettelkasten format with a timestamp and a suffix.
    local suffix = ""
    if title ~= nil then
      -- If title is given, transform it into valid file name.
      suffix = title:gsub(" ", "-"):gsub("[^A-Za-z0-9-]", ""):lower()
    else
      -- If title is nil, just add 4 random uppercase letters to the suffix.
      for _ = 1, 4 do
        suffix = suffix .. string.char(math.random(65, 90))
      end
    end
    return tostring(suffix)
  end,
}
require("todo-comments").setup {
  keywords = {
    PROJECT = {
      icon = " ", -- icon used for the sign, and in search results
      color = "info", -- can be a hex color, or a named color (see below)
      -- signs = false, -- configure signs for some keywords individually
    },
  },
}

require("nvim-treesitter.configs").setup {
  -- Add languages to be installed here that you want installed for treesitter
  ensure_installed = { "go", "lua", "rust", "toml", "typescript", "help", "bash", "markdown_inline", "markdown",
    "dockerfile" },

  highlight = { enable = true },
  auto_install = true,
  rainbow = {
    enable = true,
    extended_mode = true,
    max_file_lines = nil,
  },
  indent = {
    enable = true,
    additional_vim_regex_highlighting = { "markdown" },
  },
  incremental_selection = {
    enable = true,
    keymaps = {
      init_selection = "<c-space>",
      node_decremental = "<c-h>",
      node_incremental = "<c-space>",
      scope_incremental = "<c-s>",
    },
  },
  textobjects = {
    swap = {
      enable = true,
      swap_next = {
        ["<leader>a"] = "@parameter.inner",
      },
      swap_previous = {
        ["<leader>b"] = "@parameter.inner",
      },
    },
    lsp_interop = {
      enable = true,
      border = "none",
      peek_definition_code = {
        ["<leader>dF"] = "@function.outer",
      },
    },
    select = {
      enable = true,

      -- Automatically jump forward to textobj, similar to targets.vim
      lookahead = true,

      keymaps = {
        -- You can use the capture groups defined in textobjects.scm
        ["af"] = "@function.outer",
        ["if"] = "@function.inner",
        ["ac"] = "@class.outer",
        -- You can optionally set descriptions to the mappings (used in the desc parameter of
        -- nvim_buf_set_keymap) which plugins like which-key display
        ["ic"] = { query = "@class.inner", desc = "Select inner part of a class region" },
      },
      -- You can choose the select mode (default is charwise 'v')
      --
      -- Can also be a function which gets passed a table with the keys
      -- * query_string: eg '@function.inner'
      -- * method: eg 'v' or 'o'
      -- and should return the mode ('v', 'V', or '<c-v>') or a table
      -- mapping query_strings to modes.
      selection_modes = {
        ["@parameter.outer"] = "v", -- charwise
        ["@function.outer"] = "V",  -- linewise
        ["@class.outer"] = "<c-v>", -- blockwise
      },
      -- If you set this to `true` (default is `false`) then any textobject is
      -- extended to include preceding or succeeding whitespace. Succeeding
      -- whitespace has priority in order to act similarly to eg the built-in
      -- `ap`.
      --
      -- Can also be a function which gets passed a table with the keys
      -- * query_string: eg '@function.inner'
      -- * selection_mode: eg 'v'
      -- and should return true of false
      include_surrounding_whitespace = false,
    },
  },
}

local ts_repeat_move = require "nvim-treesitter.textobjects.repeatable_move"

-- Optionally, make builtin f, F, t, T also repeatable with ; and ,
vim.keymap.set({ "n", "x", "o" }, "f", ts_repeat_move.builtin_f)
vim.keymap.set({ "n", "x", "o" }, "F", ts_repeat_move.builtin_F)
vim.keymap.set({ "n", "x", "o" }, "t", ts_repeat_move.builtin_t)
vim.keymap.set({ "n", "x", "o" }, "T", ts_repeat_move.builtin_T)

require("femaco").setup {
  -- what to do after opening the float
  post_open_float = function(winnr)
    if vim.bo.filetype == "rust" then
      require("rust-tools.standalone").start_standalone_client()
    end
  end,
}


require("which-key").setup {
  triggers_blacklist = {
    -- list of mode / prefixes that should never be hooked by WhichKey
    -- this is mostly relevant for keymaps that start with a native binding
    n = { "g" },
  },
  plugins = {
    marks = true,       -- shows a list of your marks on ' and `
    registers = true,   -- shows your registers on " in NORMAL or <C-r> in INSERT mode
    spelling = {
      enabled = true,   -- enabling this will show WhichKey when pressing z= to select spelling suggestions
      suggestions = 20, -- how many suggestions should be shown in the list?
    },
  },
}

require("lualine").setup {
  options = {
    theme = "tokyonight",
    extensions = { "nvim-dap-ui" },
  },
}

require("nvim-surround").setup {
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
}

require("leap").add_default_mappings()

-- Color name (:help cterm-colors) or ANSI code
-- there are some defaults for image directory and image name, you can change them
vim.g.mdip_imgdir = "_media"
vim.g.mdip_imgname = "image"
vim.g["plantuml_previewer#viewer_path"] = "~/.vim/bundle/plantuml-previewer.vim/viewer"
vim.g["plantuml_previewer#debug_mode"] = 0
-- setup custom emmet snippets
vim.g.user_emmet_settings = "webapi#json#decode(join(readfile(expand('~/.snippets_custom.json')), \"\n\"))"
vim.g.indentLine_char = "⦙"
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
vim.g.syntastic_python_checkers = "['flake8']"
-- setup for terraform
vim.g.terraform_fmt_on_save = 1
vim.g.terraform_align = 1
-- setup for ctrlp
vim.g.ctrlp_map = "<c-p>"
vim.g.ctrlp_cmd = "CtrlPMixed"
vim.g.ctrlp_working_path_mode = "ra"
vim.g.ctrlp_custom_ignore = "\\v[\\/]\\.(git|hg|svn)$"
vim.g.ctrlp_custom_ignore = {
  dir = { "\\v[\\/]\\.(git|hg|svn)$" },
  file = { "\\v\\.(exe|so|dll)$" },
  link = { "some_bad_symbolic_links" },
}
-- setup for indent line
vim.g.indentLine_char = "|"
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
-- Scrollfix
vim.g.scrollfix = -1
vim.g.rnvimr_enable_picker = 1
-- Startify
vim.g.startify_change_to_dir = 1
vim.g.startify_session_persistence = 0
vim.g.startify_change_to_vsc_root = 1
vim.g.startify_session_number = 0
vim.g.startify_files_number = 10
vim.g.startify_session_delete_buffers = 0
vim.g.startify_skiplist = {
  "^/tmp",
}
vim.g.startify_commands = {
  { "Search Dev    :SPC fd", "Telescope find_files search_dirs=~/dev,--hidden,--with-filename" },
  { "Search Repos  :SPC fr", "lua require'telescope'.extensions.repo.list{search_dirs = {\"~/dev\"}}" },
  { "Ranger        :ALT o",  "RnvimrToggle" },
  { "Change Color  :SPC fc", "Telescope colorscheme" },
  { "Transparent Bg:SPC tr", "TransparentEnable" },
  { "Pick Emoji    :SPC fm", "Telescope emoji" },
}
vim.g.startify_bookmarks = {
  "~/.config/nvim/lua",
  "~/.zshrc",
  "~/.tmux.conf",
  "~/.taskrc",
  "~/.task/hooks",
  "~/.config/ranger/rc.conf",
  "~/shortcuts.md",
  "/usr/local/share/zsh/site-functions",
  "~/dev/dotfiles/.config/nvim/lua/projects/module.lua",
  "~/scripts/__project_mappings.conf",
  "~/.taskopenrc",
  "~/.oh-my-zsh/plugins/tmuxinator/_mst",
  "~/.config/taskwarrior-tui/shortcut-scripts",
  "~/.local/share/nvim/site/pack/packer/start",
}
vim.g.startify_custom_header = "startify#pad(split(system('fortune -s | cowsay | lolcat; date'), '\n'))"
