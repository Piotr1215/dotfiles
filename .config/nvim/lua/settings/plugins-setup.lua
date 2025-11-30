-- Settings for plugins
vim.notify = require "notify"
require("mason").setup()

-- Load LuaSnip configuration early (before cmp)
require "config.luasnip"

require("typeit").setup {
  default_speed = 30, -- Default typing speed (milliseconds)
  default_pause = "paragraph", -- Default pause behavior ('line' or 'paragraph')
}

require("eyeliner").setup {
  highlight_on_key = true, -- this must be set to true for dimming to work!
}

--- the parameter is optional
---@diagnostic disable-next-line: missing-parameter
require("urlview").setup()

require("Comment").setup()

vim.filetype.add {
  pattern = {
    [".*/.github/workflows/.*%.yml"] = "yaml.ghaction",
    [".*/.github/workflows/.*%.yaml"] = "yaml.ghaction",
  },
}

require("lint").linters_by_ft = {
  ["yaml.ghaction"] = { "actionlint" },
}

require("docusaurus").setup()

require("gitsigns").setup {
  on_attach = function(bufnr)
    local gitsigns = require "gitsigns"

    local function map(mode, l, r, opts)
      opts = opts or {}
      opts.buffer = bufnr
      vim.keymap.set(mode, l, r, opts)
    end

    -- Navigation
    map("n", "]h", function()
      if vim.wo.diff then
        vim.cmd.normal { "]h", bang = true }
      else
        gitsigns.nav_hunk "next"
      end
    end, { desc = "Go to next hunk" })

    map("n", "[h", function()
      if vim.wo.diff then
        vim.cmd.normal { "[h", bang = true }
      else
        gitsigns.nav_hunk "prev"
      end
    end, { desc = "Go to previous hunk" })

    -- Actions
    map("n", "<leader>hs", gitsigns.stage_hunk, { desc = "Stage hunk" })
    map("n", "<leader>sh", gitsigns.select_hunk, { desc = "Stage hunk" })
    map("n", "<leader>hr", gitsigns.reset_hunk, { desc = "Reset hunk" })
    map("v", "<leader>hs", function()
      gitsigns.stage_hunk { vim.fn.line ".", vim.fn.line "v" }
    end, { desc = "Stage hunk (visual)" })
    map("v", "<leader>hr", function()
      gitsigns.reset_hunk { vim.fn.line ".", vim.fn.line "v" }
    end, { desc = "Reset hunk (visual)" })
    map("n", "<leader>hS", gitsigns.stage_buffer, { desc = "Stage buffer" })
    map("n", "<leader>hu", gitsigns.stage_hunk, { desc = "Undo stage hunk" })
    map("n", "<leader>hR", gitsigns.reset_buffer, { desc = "Reset buffer" })
    map("n", "<leader>hp", gitsigns.preview_hunk, { desc = "Preview hunk" })
    map("n", "<leader>hb", function()
      gitsigns.blame_line { full = true }
    end, { desc = "Blame line" })
    map("n", "<leader>tb", gitsigns.toggle_current_line_blame, { desc = "Toggle line blame" })
    map("n", "<leader>hd", gitsigns.diffthis, { desc = "Diff this" })
    map("n", "<leader>hD", function()
      gitsigns.diffthis "~"
    end, { desc = "Diff this (against HEAD)" })
    map("n", "<leader>td", gitsigns.preview_hunk_inline, { desc = "Toggle deleted" })

    -- Text object
    map({ "o", "x" }, "Ih", ":<C-U>Gitsigns select_hunk<CR>", { desc = "Select hunk" })
  end,
}

require("yanksearch").setup {
  lines_above = 0,
  lines_below = 0,
  lines_around = 0, -- This will override lines_above and lines_below if set to a non-zero value
}

require("gp").setup {
  -- default agent names set during startup, if nil last used agent is used
  -- Claude35 or ChatGPT4
  whisper = {
    rec_cmd = { "sox", "-c", "1", "--buffer", "32", "-d", "rec.wav", "trim", "0", "60:00" },
  },

  default_command_agent = "Claude4",
  default_chat_agent = "Claude4",
  hooks = {
    -- Example of adding a custom command to explain selected code
    ExplainCode = function(gp, params)
      local template = "I have the following code from {{filename}}:\n\n"
        .. "```{{filetype}}\n{{selection}}\n```\n\n"
        .. "Please explain the code above."
      local agent = gp.get_chat_agent()
      gp.Prompt(params, gp.Target.popup, agent, template)
    end,

    -- Example of adding a custom command to write unit tests for selected code
    ImproveWriting = function(gp, params)
      local template = "Here is some code from {{filename}}:\n\n"
        .. "```{{filetype}}\n{{selection}}\n```\n\n"
        .. "Please improve writing style and readability."
      local agent = gp.get_command_agent()
      gp.Prompt(params, gp.Target.rewrite, agent, template)
    end,

    -- Example of adding a custom command to write unit tests for selected code
    WriteUnitTests = function(gp, params)
      local template = "Here is some code from {{filename}}:\n\n"
        .. "```{{filetype}}\n{{selection}}\n```\n\n"
        .. "Can you generate unit tests for the code above?"
      local agent = gp.get_command_agent()
      gp.Prompt(params, gp.Target.vnew, agent, template)
    end,

    -- Example of adding a custom command to perform a code review
    CodeReview = function(gp, params)
      local template = "Please review the following code from {{filename}}:\n\n"
        .. "```{{filetype}}\n{{selection}}\n```\n\n"
        .. "Look for potential issues and suggest improvements."
      local agent = gp.get_chat_agent()
      gp.Prompt(params, gp.Target.enew "markdown", agent, template)
    end,

    -- Custom Web Search Command using Perplexity
    WebSearch = function(gp, params)
      local template =
        "Search the internet using Perplexity for: '{{command}}'. Provide a concise answer and include sources."
      local agent = gp.get_command_agent "pplx"
      gp.Prompt(params, gp.Target.vnew "markdown", agent, template)
    end,

    -- Custom Web Search Command using Perplexity
    WebSearchSelection = function(gp, params)
      local template = "{{filename}}:\n\n"
        .. "```{{filetype}}\n{{selection}}\n```\n\n"
        .. "{{command}}\n"
        .. "Provide a concise answer and include sources."
      local agent = gp.get_command_agent "pplx"
      gp.Prompt(params, gp.Target.vnew "markdown", agent, template, "Optional instructions:")
    end,
  },
  providers = {
    anthropic = {
      disable = false,
      endpoint = "https://api.anthropic.com/v1/messages",
      secret = os.getenv "ANTHROPIC_API_KEY",
    },
    pplx = {
      endpoint = "https://api.perplexity.ai/chat/completions",
      secret = os.getenv "PPLX_API_KEY", -- Ensure you have this set in your environment
    },
  },
  agents = {
    -- Disable ChatGPT 3.5
    {
      name = "ChatGPT3-5",
      disable = true,
    },
    {
      provider = "anthropic",
      name = "Claude37",
      chat = true,
      command = true,
      -- string with model name or table with model name and parameters
      model = { model = "claude-3-7-sonnet-latest", temperature = 0, top_p = 0 },
      -- system prompt (use this to specify the persona/role of the AI)
      system_prompt = "You are a specialized coding AI assistant.\n\n"
        .. "The user provided the additional info about how they would like you to respond:\n\n"
        .. "- If you're unsure don't guess and say you don't know instead.\n"
        .. "- Ask question if you need clarification to provide better answer.\n"
        .. "- Think deeply and carefully from first principles step by step.\n"
        .. "- Make your answers short, concise, to the point and helpful.\n"
        .. "- Produce only valid and actionable code.\n"
        .. "- Include only essential response like code etc, DO NOT provide explanations unless specifically asked for\n"
        .. "- Take a deep breath; You've got this!",
    },

    {
      provider = "anthropic",
      name = "Claude35",
      chat = true,
      command = true,
      -- string with model name or table with model name and parameters
      model = { model = "claude-3-5-sonnet-20241022", temperature = 0, top_p = 0 },
      -- system prompt (use this to specify the persona/role of the AI)
      system_prompt = "You are a specialized coding AI assistant.\n\n"
        .. "The user provided the additional info about how they would like you to respond:\n\n"
        .. "- If you're unsure don't guess and say you don't know instead.\n"
        .. "- Ask question if you need clarification to provide better answer.\n"
        .. "- Think deeply and carefully from first principles step by step.\n"
        .. "- Make your answers short, concise, to the point and helpful.\n"
        .. "- Produce only valid and actionable code.\n"
        .. "- Include only essential response like code etc, DO NOT provide explanations unless specifically asked for\n"
        .. "- Take a deep breath; You've got this!",
    },

    {
      provider = "anthropic",
      name = "Claude4",
      chat = true,
      command = true,
      -- string with model name or table with model name and parameters
      model = { model = "claude-sonnet-4-20250514", temperature = 0, top_p = 0 },
      -- system prompt (use this to specify the persona/role of the AI)
      system_prompt = "You are a specialized coding AI assistant.\n\n"
        .. "The user provided the additional info about how they would like you to respond:\n\n"
        .. "- If you're unsure don't guess and say you don't know instead.\n"
        .. "- Ask question if you need clarification to provide better answer.\n"
        .. "- Think deeply and carefully from first principles step by step.\n"
        .. "- Make your answers short, concise, to the point and helpful.\n"
        .. "- Produce only valid and actionable code.\n"
        .. "- Include only essential response like code etc, DO NOT provide explanations unless specifically asked for\n"
        .. "- Take a deep breath; You've got this!",
    },
    {
      name = "ChatGPT4.1",
      chat = true,
      command = true,
      -- string with model name or table with model name and parameters
      model = { model = "gpt-4.1", temperature = 0.1, top_p = 1 },
      -- system prompt (use this to specify the persona/role of the AI)
      system_prompt = "You are a specialized coding AI assistant.\n\n"
        .. "The user provided the additional info about how they would like you to respond:\n\n"
        .. "- If you're unsure don't guess and say you don't know instead.\n"
        .. "- Ask question if you need clarification to provide better answer.\n"
        .. "- Think deeply and carefully from first principles step by step.\n"
        .. "- Make your answers short, concise, to the point and helpful.\n"
        .. "- Produce only valid and actionable code.\n"
        .. "- Include only essential response like code etc, DO NOT provide explanations unless specifically asked for\n"
        .. "- Take a deep breath; You've got this!",
    },
    {
      provider = "openai",
      name = "o1-preview",
      chat = true,
      command = true,
      model = { model = "o1-preview", temperature = 0.7, top_p = 1 },
      system_prompt = "You are a specialized coding AI assistant.\n\n"
        .. "The user provided the additional info about how they would like you to respond:\n\n"
        .. "- If you're unsure don't guess and say you don't know instead.\n"
        .. "- Ask question if you need clarification to provide better answer.\n"
        .. "- Produce only valid and actionable code.\n"
        .. "- Include only essential response like code etc, DO NOT provide explanations unless specifically asked for\n",
    },
    {
      provider = "openai",
      name = "o3-mini",
      chat = true,
      command = true,
      model = { model = "o3-mini", temperature = 0.3, top_p = 1 },
      system_prompt = "You are a specialized coding AI assistant.\n\n"
        .. "The user provided the additional info about how they would like you to respond:\n\n"
        .. "- Produce only valid and actionable code.\n",
    },
    -- Perplexity agent
    {
      provider = "pplx",
      name = "pplx", -- Perplexity agent
      chat = true,
      command = true,
      model = { model = "sonar" },
      system_prompt = "You are specialized internet search assistant.",
    },
  },
}

require("mini.align").setup()
require("mini.ai").setup {
  custom_textobjects = {
    ["|"] = false, -- Disable | text object
    n = false, -- Disable n text object
    l = false,
    -- Search match text object (uses last search pattern from / or ?)
    -- Usage: da/ (delete around search), ci/ (change inner search), ya/ (yank around search)
    ["/"] = require("user_functions.search_text_object").search_textobject,
    ["*"] = { { "%*%*()[^*]+()%*%*", "%*()[^*]+()%*" } }, -- *italic* and **bold**
  },
}
require("mini.files").setup {
  windows = {
    preview = true,
    width_focus = 100,
    width_preview = 100,
  },
}

require("mini.bracketed").setup {
  buffer = { suffix = "", options = {} },
  comment = { suffix = "", options = {} },
  conflict = { suffix = "", options = {} },
  diagnostic = { suffix = "", options = {} },
  file = { suffix = "", options = {} },
  indent = { suffix = "i", options = {} },
  jump = { suffix = "", options = {} },
  location = { suffix = "", options = {} },
  oldfile = { suffix = "", options = {} },
  quickfix = { suffix = "", options = {} },
  treesitter = { suffix = "", options = {} },
  undo = { suffix = "", options = {} },
  window = { suffix = "", options = {} },
  yank = { suffix = "", options = {} },
}

require("go").setup {
  gofmt = "gofumpt",
  lsp_gofumpt = true,
}
require("dap-python").setup "~/.virtualenvs/debugpy/bin/python"

require("goto-preview").setup {}

require("no-neck-pain").setup {
  width = 75,
  buffers = {
    colors = {
      background = "#000000",
    },
    right = {
      enabled = false,
    },
  },
}

require("mdeval").setup {
  -- Don't ask before executing code blocks
  require_confirmation = false,
  -- Change code blocks evaluation options.
  eval_options = {
    -- Set custom configuration for C++
    go = {
      command = { "go", "run" },
      extension = "go",
      exec_type = "interpreted", -- Since Go runs as 'go run' for scripts
      language_code = "go", -- Assuming the plugin can use this to identify code blocks
    },
    zsh = {
      command = { "zsh", "-c" },
      exec_type = "interpreted",
      language_code = "zsh",
      extension = "sh",
      default_header = [[
#!/usr/bin/env zsh
      ]],
    },
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

require("obsidian").setup {
  workspaces = {
    {
      name = "main",
      path = "~/dev/obsidian/decoder",
      -- Optional, override certain settings.
      overrides = {
        notes_subdir = "Notes",
      },
    },
  },
  disable_frontmatter = false,
  legacy_commands = false, -- Disable deprecated commands
  -- open_app_foreground = true,
  templates = {
    subdir = "Templates",
    date_format = "%Y-%m-%d-%a",
    time_format = "%H:%M",
  },
  new_notes_location = "notes_subdir",
  -- Optional, configure additional syntax highlighting / extmarks.
  ui = {
    enable = false, -- set to false to disable all additional syntax features
    update_debounce = 200, -- update delay after a text change (in milliseconds)
    -- Define how various check-boxes are displayed
    external_link_icon = { char = "", hl_group = "ObsidianExtLinkIcon" },
    -- Replace the above with this if you don't have a patched font:
    -- external_link_icon = { char = "", hl_group = "ObsidianExtLinkIcon" },
    reference_text = { hl_group = "ObsidianRefText" },
    highlight_text = { hl_group = "ObsidianHighlightText" },
    tags = { hl_group = "ObsidianTag" },
    hl_groups = {
      -- The options are passed directly to `vim.api.nvim_set_hl()`. See `:help nvim_set_hl`.
      ObsidianTodo = { bold = true, fg = "#f78c6c" },
      ObsidianDone = { bold = true, fg = "#89ddff" },
      ObsidianRightArrow = { bold = true, fg = "#f78c6c" },
      ObsidianTilde = { bold = true, fg = "#ff5370" },
      ObsidianRefText = { underline = true, fg = "#c792ea" },
      ObsidianExtLinkIcon = { fg = "#c792ea" },
      ObsidianTag = { italic = true, fg = "#89ddff" },
      ObsidianHighlightText = { bg = "#75662e" },
    },
  },
  follow_url_func = function(url)
    -- Open the URL in the default web browser.
    vim.fn.jobstart { "xdg-open", url } -- linux
  end,
  finder = "telescope.nvim",
  note_path_func = function(spec)
    -- This is equivalent to the default behavior.
    local path = spec.dir / tostring(spec.title)
    return path:with_suffix ".md"
  end,

  -- Always use wikilinks, not markdown links
  preferred_link_style = "wiki",

  -- Use simple link style (just note name, no path or .md extension)
  wiki_link_func = "use_alias_only",

  -- Use just the note name as ID (obsidian.nvim handles path resolution)
  note_id_func = function(title)
    -- Return just the title without path or extension
    return title
  end,

  -- Configure keymaps using callbacks (community fork API)
  callbacks = {
    enter_note = function(_, note)
      -- gf to follow links (uses :Obsidian follow_link command)
      vim.keymap.set("n", "gf", "<cmd>Obsidian follow_link<cr>", {
        buffer = note.bufnr,
        desc = "Follow Obsidian link",
      })

      -- <CR> to follow links or toggle checkboxes
      vim.keymap.set("n", "<CR>", "<cmd>Obsidian smart_action<cr>", {
        buffer = note.bufnr,
        desc = "Obsidian smart action",
      })
    end,
  },

  completion = {
    nvim_cmp = true, -- if using nvim-cmp, otherwise set to false
  },
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

-- Workaround for treesitter highlighting error in Neovim 0.11+
-- Override nvim_buf_set_extmark to handle out of range errors
local original_set_extmark = vim.api.nvim_buf_set_extmark
vim.api.nvim_buf_set_extmark = function(buffer, ns_id, line, col, opts)
  local ok, result = pcall(original_set_extmark, buffer, ns_id, line, col, opts)
  if not ok then
    if
      result:match "Invalid 'end_col': out of range"
      or result:match "Invalid 'end_row': out of range"
      or result:match "Invalid 'line': out of range"
    then
      return 0 -- Return a dummy extmark id
    end
    error(result)
  end
  return result
end

require("nvim-treesitter.configs").setup {
  -- Add languages to be installed here that you want installed for treesitter
  ensure_installed = {
    "go",
    "hurl",
    "lua",
    "rust",
    "toml",
    "typescript",
    "bash",
    "markdown_inline",
    "markdown",
    "dockerfile",
  },
  -- List of parsers to ignore installing
  ignore_install = {},
  -- Install parsers synchronously (only applied to `ensure_installed`)
  sync_install = false,
  -- List of parsers to always install, useful for parsers without filetype
  modules = {},

  highlight = { enable = true },
  auto_install = true,
  rainbow = {
    enable = true,
    extended_mode = true,
    max_file_lines = nil,
  },
  indent = {
    enable = false,
    -- disable yaml indenting because the grammar is too simplistic, other plugins do it better
    disable = { "yaml" },
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
      enable = false,
      swap_next = {
        ["<leader>a"] = "@parameter.inner",
      },
      swap_previous = {
        ["<leader>b"] = "@parameter.inner",
      },
    },
    move = {
      enable = true,
      disable = { "yaml", "markdown" },
      set_jumps = true, -- whether to set jumps in the jumplist
      goto_next_start = {
        ["]m"] = "@function.outer",
        ["]]"] = "@class.outer",
        ["]a"] = "@parameter.inner",
      },
      goto_next_end = {
        ["]M"] = "@function.outer",
        ["]["] = "@class.outer",
      },
      goto_previous_start = {
        ["[m"] = "@function.outer",
        ["[["] = "@class.outer",
        ["[a"] = "@parameter.inner",
      },
      goto_previous_end = {
        ["[M"] = "@function.outer",
        ["[]"] = "@class.outer",
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
      disable = { "yaml" },

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
        ["@function.outer"] = "V", -- linewise
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

require("femaco").setup {
  -- what to do after opening the float
  post_open_float = function(winnr)
    if vim.bo.filetype == "rust" then
      require("rust-tools.standalone").start_standalone_client()
    end
  end,
}

require("which-key").setup {
  notify = false,
  plugins = {
    marks = true, -- shows a list of your marks on ' and `
    registers = true, -- shows your registers on " in NORMAL or <C-r> in INSERT mode
    spelling = {
      enabled = true, -- enabling this will show WhichKey when pressing z= to select spelling suggestions
      suggestions = 20, -- how many suggestions should be shown in the list?
    },
  },
}

require("lualine").setup {
  options = {
    theme = "tokyonight",
    extensions = { "nvim-dap-ui" },
  },
  sections = {
    lualine_a = { "mode" },
    lualine_b = { "branch", "diff", "diagnostics" },
    lualine_c = {
      "filename",
    },
    lualine_x = { "encoding", "fileformat", "filetype" },
    lualine_y = { "progress" },
    lualine_z = { "location" },
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

-- Color name (:help cterm-colors) or ANSI code
-- there are some defaults for image directory and image name, you can change them
vim.g.mdip_imgdir = "_media"
vim.g.mdip_imgname = "image"
vim.g["plantuml_previewer#viewer_path"] = "~/.vim/bundle/plantuml-previewer.vim/viewer"
vim.g["plantuml_previewer#debug_mode"] = 0
vim.g["plantuml_previewer#plantuml_jar_path"] = "/usr/local/bin/plantuml.jar"
-- setup custom emmet snippets
vim.g.user_emmet_settings = "webapi#json#decode(join(readfile(expand('~/.snippets_custom.json')), \"\n\"))"
vim.g.indentLine_char = "⦙"
-- setup for netrw
vim.g.netrw_winsize = 30
vim.g.netrw_banner = 0
vim.g.netrw_keepdir = 0
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
-- Send to window
vim.g.sendtowindow_use_defaults = 0
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
vim.g.startify_commands = {}
vim.g.startify_bookmarks = {}
vim.g.startify_custom_header = "startify#pad(split(system('fortune -s | cowsay | lolcat; date'), '\n'))"
