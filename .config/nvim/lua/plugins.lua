-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"
if not (vim.uv or vim.uv).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system { "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

return require("lazy").setup({
  -- AI {{{
  "github/copilot.vim",
  {
    "folke/sidekick.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      nes = {
        enabled = false,
        debounce = 100,
        trigger = {
          events = { "InsertLeave", "TextChanged", "CursorHold" },
        },
      },
      cli = {
        mux = {
          backend = "tmux",
          enabled = true,
        },
      },
    },
  },
  "robitx/gp.nvim",
  -- }}}
  -- Editor Extensions {{{
  ---@type LazySpec
  { "jinh0/eyeliner.nvim" },
  { "mfussenegger/nvim-lint" },
  {
    "mikavilpas/yazi.nvim",
    event = "VeryLazy",
    keys = {
      -- 👇 in this section, choose your own keymappings!
      {
        "<leader>-",
        "<cmd>Yazi<cr>",
        desc = "Open yazi at the current file",
      },
      {
        -- Open in the current working directory
        "<leader>cw",
        "<cmd>Yazi cwd<cr>",
        desc = "Open the file manager in nvim's working directory",
      },
      {
        -- NOTE: this requires a version of yazi that includes
        -- https://github.com/sxyazi/yazi/pull/1305 from 2024-07-18
        "<c-up>",
        "<cmd>Yazi toggle<cr>",
        desc = "Resume the last yazi session",
      },
    },
    opts = {
      -- if you want to open yazi instead of netrw, see below for more info
      open_for_directories = false,
      keymaps = {
        show_help = "<f1>",
      },
    },
  },
  {
    "nvchad/showkeys",
    cmd = "ShowkeysToggle",
    opts = {
      timeout = 2,
      maxkeys = 5,
      position = "top-right",
      show_count = true,
      excluded_modes = { "i" },
    },
  }, -- more opts
  "MunifTanjim/nui.nvim",
  "stevearc/dressing.nvim",
  "tyru/open-browser.vim",
  "gcmt/taboo.vim",

  "towolf/vim-helm",
  "jbyuki/one-small-step-for-vimkind",
  { "alexghergh/nvim-tmux-navigation", opts = { disable_when_zoomed = true } },
  "romainl/vim-cool",
  "yssl/QFEnter",
  "jesseleite/nvim-macroni",
  "nosduco/remote-sshfs.nvim",
  { "nvim-lua/plenary.nvim", lazy = true },
  {
    "windwp/nvim-autopairs",
    config = function()
      local npairs = require "nvim-autopairs"
      local cond = require "nvim-autopairs.conds"

      npairs.setup {}

      -- Remove the triple backtick rule for markdown
      npairs.remove_rule "```"

      -- Also prevent auto-pairing of backticks in markdown
      npairs.get_rule("`"):with_pair(cond.not_filetypes { "markdown", "md" })
    end,
  },
  "jonarrien/telescope-cmdline.nvim",
  { "wintermute-cell/gitignore.nvim", dependencies = "nvim-telescope/telescope.nvim" },
  "ionide/Ionide-vim",
  "rcarriga/nvim-notify",
  "tpope/vim-rhubarb",
  "David-Kunz/gen.nvim",
  "RRethy/nvim-align",
  "vim-scripts/scrollfix",
  "echasnovski/mini.nvim",
  "mattn/emmet-vim",
  "mattn/webapi-vim",
  "mhinz/vim-startify",
  "numToStr/Comment.nvim",
  "lewis6991/gitsigns.nvim",
  "tpope/vim-fugitive",
  "Piotr1215/telescope-crossplane.nvim",
  { "kylechui/nvim-surround", opts = {} },
  "axieax/urlview.nvim",
  "folke/which-key.nvim",
  "lukas-reineke/indent-blankline.nvim",
  "machakann/vim-swap",
  "austintaylor/vim-commaobject",
  "ferrine/md-img-paste.vim",
  {
    "cuducos/yaml.nvim",
    ft = { "yaml" }, -- optional
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-telescope/telescope.nvim", -- optional
    },
  },
  -- 'https://gitlab.com/madyanov/svart.nvim',
  "kevinhwang91/nvim-bqf", -- better quickfix window
  -- }}}
  -- System Integration {{{
  {
    "junegunn/fzf",
    build = "./install --bin",
  },
  "junegunn/fzf.vim",
  "nvim-tree/nvim-web-devicons", -- optional, for file icon
  -- }}}
  -- Telescope {{{
  "danielpieper/telescope-tmuxinator.nvim",
  "jvgrootveld/telescope-zoxide",
  { "ellisonleao/glow.nvim", opts = {} },
  "xiyaowong/telescope-emoji.nvim",
  "nvim-telescope/telescope-symbols.nvim",
  "cljoly/telescope-repo.nvim",
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      { "nvim-lua/popup.nvim" },
      { "nvim-telescope/telescope-live-grep-args.nvim", version = "^1.0.0" },
      { "nvim-telescope/telescope-github.nvim" },
    },
  },
  {
    "nvim-telescope/telescope-file-browser.nvim",
  },
  {
    "nvim-telescope/telescope-fzf-native.nvim",
    build = "make",
  },
  "smartpde/telescope-recent-files",
  -- }}}
  -- LSP {{{
  "ray-x/lsp_signature.nvim",
  "ibhagwan/fzf-lua",
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
  "onsails/lspkind-nvim",
  "williamboman/mason.nvim",
  "williamboman/mason-lspconfig.nvim",
  {
    {
      "folke/lazydev.nvim",
      ft = "lua", -- only load on lua files
      opts = {
        library = {
          -- See the configuration section for more details
          -- Load luvit types when the `vim.uv` word is found
          { path = "luvit-meta/library", words = { "vim%.uv" } },
        },
      },
    },
    { "Bilal2453/luvit-meta", lazy = true }, -- optional `vim.uv` typings
    { -- optional completion source for require statements and module annotations
      "hrsh7th/nvim-cmp",
      opts = function(_, opts)
        opts.sources = opts.sources or {}
        table.insert(opts.sources, {
          name = "lazydev",
          group_index = 0, -- set group index to 0 to skip loading LuaLS completions
        })
      end,
    },
    -- { "folke/neodev.nvim", enabled = false }, -- make sure to uninstall or disable neodev.nvim
  },
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    priority = 100,
    init = function()
      -- Prevent the plugin from loading its deprecated framework
      vim.g.lspconfig = 1
    end,
    config = function()
      -- We use our own compatibility wrapper for plugins that need lspconfig
    end,
  },
  { "folke/trouble.nvim", dependencies = "kyazdani42/nvim-web-devicons", opts = {} },
  "hrsh7th/cmp-nvim-lsp-signature-help",
  {
    "L3MON4D3/LuaSnip",
    -- follow latest release.
    version = "v2.*",
    -- install jsregexp (optional!).
    build = "make install_jsregexp",
    dependencies = {
      "rafamadriz/friendly-snippets",
    },
  },
  "saadparwaiz1/cmp_luasnip",
  { "shortcuts/no-neck-pain.nvim", version = "*" },

  "leoluz/nvim-dap-go",
  {
    "rcarriga/nvim-dap-ui",
    dependencies = {
      "mfussenegger/nvim-dap",
    },
  },
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
  },
  "mfussenegger/nvim-dap-python",
  -- }}}
  -- Snippets {{{
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "nvim-treesitter",
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
    },
  },
  "hrsh7th/cmp-nvim-lua",
  -- }}}
  -- Programming {{{
  "ii14/neorepl.nvim",
  "theHamsta/nvim-dap-virtual-text",
  "stevearc/dressing.nvim",
  { "saecki/crates.nvim", opts = {} },
  {
    "mrcjkb/rustaceanvim",
    version = "^5",
    lazy = false,
    ft = { "rust" },
  },
  "IndianBoy42/tree-sitter-just",
  "NoahTheDuke/vim-just",
  "ray-x/go.nvim",
  "ray-x/guihua.lua", -- recommended if need floating window support
  "rmagatti/goto-preview",
  "nvim-treesitter/nvim-treesitter-textobjects",
  {
    "chrisgrieser/nvim-various-textobjs",
    event = "VeryLazy",
    opts = {
      keymaps = {
        useDefaults = true,
        disabledDefaults = {
          "is",
          "iS",
          "in",
          "iN",
          "as",
          "aS",
          "io",
          "ao",
          "gG",
          "im",
          "am",
          "!",
          "iy",
          "ay",
          "an",
        },
      },
    },
  },
  -- }}}
  -- Markdown {{{
  "jubnzv/mdeval.nvim",
  {
    "AckslD/nvim-FeMaco.lua",
    config = 'require("femaco").setup()',
  },
  "sbdchd/neoformat",
  "ixru/nvim-markdown",
  "dhruvasagar/vim-open-url",
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = "cd app && yarn install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    ft = { "markdown" },
  },
  "javiorfo/nvim-soil",

  -- Optional for puml syntax highlighting:
  "javiorfo/nvim-nyctophilia",
  "weirongxu/plantuml-previewer.vim",
  -- }}}
  -- My Plugins {{{
  { "Piotr1215/yanksearch.nvim" },
  "Piotr1215/typeit.nvim",
  {
    "Piotr1215/docusaurus.nvim",
    dev = true,
    dependencies = {
      "nvim-telescope/telescope.nvim",
    },
    config = function()
      require("docusaurus").setup {
        -- Optional: customize these if needed
        -- components_dir = nil, -- auto-detects {git-root}/src/components
        -- partials_dirs = { "_partials", "_fragments", "_code" },
        -- allowed_site_paths = { "^docs/_partials/", "^docs/_fragments/", "^docs/_code/" },
      }

      -- Content insertion keymaps
      vim.keymap.set("n", "<leader>ic", "<cmd>DocusaurusInsertComponent<cr>", { desc = "Insert Component" })
      vim.keymap.set("n", "<leader>ip", "<cmd>DocusaurusInsertPartial<cr>", { desc = "Insert Partial" })
      vim.keymap.set("n", "<leader>ib", "<cmd>DocusaurusInsertCodeBlock<cr>", { desc = "Insert CodeBlock" })
      vim.keymap.set("n", "<leader>iu", "<cmd>DocusaurusInsertURL<cr>", { desc = "Insert URL" })

      -- API browser keymap
      vim.keymap.set("n", "<leader>dpa", "<cmd>DocusaurusBrowseAPI<cr>", { desc = "Browse API" })
    end,
  },
  -- }}}
  -- beam.nvim - Search and operate on distant text
  {
    "Piotr1215/beam.nvim",
    dev = true,
    config = function()
      require("beam").setup {
        prefix = ",",
        visual_feedback_duration = 150,
        cross_buffer = {
          enabled = false, -- Enable cross-buffer operations
          fuzzy_finder = "telescope", -- Uses Telescope for cross-buffer (required)
          include_hidden = false,
        },
        -- Enable beam's custom text objects (currently: im/am for markdown code blocks)
        enable_default_text_objects = true,
        -- Auto-discover custom text objects from plugins (mini.ai, treesitter, etc.)
        auto_discover_custom_text_objects = true,
        show_discovery_notification = false, -- Show what was discovered
        excluded_motions = { "Q", "R" }, -- Exclude Q and R motions from auto-discovery
        resolved_conflicts = { "m" }, -- Mark 'm' conflict as intentional (beam's im/am coexists with your custom im/am)
        smart_highlighting = false, -- Enable real-time context-aware search highlighting for delimiter text objects
        beam_scope = {
          enabled = true, -- Enable BeamScope for scoped text objects
          custom_scoped_text_objects = {
            "m", -- Markdown code blocks
            "h", -- Markdown headers
            "L", -- URL object
          },
          preview_context = 3, -- Number of context lines to show before/after in preview
          window_width = 100, -- Maximum width of the BeamScope window
        },
        experimental = {
          telescope_single_buffer = {
            enabled = false, -- Optional: Use Telescope for single buffer too
            theme = "cursor", -- Theme: 'dropdown', 'cursor', 'ivy'
            preview = true, -- Show preview pane
            winblend = 10, -- Window transparency (0-100)
          },
        },
      }
    end,
  },
  -- snacks.nvim - QoL plugins collection
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {},
  },
  -- presenterm.nvim - Neovim plugin for presenterm presentations
  {
    "Piotr1215/presenterm.nvim",
    dev = true,
    dependencies = {
      "nvim-telescope/telescope.nvim",
    },
    config = function()
      require("presenterm").setup {
        default_keybindings = true,
        picker = {
          provider = "telescope", -- Options: "telescope", "fzf", "snacks", "builtin"
        },
        preview = {
          -- Command execution flags (-xX):
          -- By default, presenterm does NOT execute commands in slides for security.
          -- The -xX flags allow presenterm to:
          --   -x: Load environment from shell config files
          --   -X: Enable command execution from +exec code blocks
          -- Required for demos that run kubectl, docker, or other shell commands.
          command = "presenterm -xX",

          -- Bi-directional sync:
          -- When enabled, navigating in markdown moves presenterm slides,
          -- and navigating in presenterm moves the markdown cursor.
          -- Requires presenterm footer with slide numbers (e.g., "1 / 10").
          presentation_preview_sync = true,

          -- Login shell environment:
          -- When true, presenterm runs in an interactive login shell (-lic flags).
          -- This loads your full shell environment (.bashrc, .zshrc, etc.).
          -- Required for commands that need environment variables like:
          --   - PATH additions (nvm, pyenv, rbenv, custom bins)
          --   - Node.js, Python version managers
          --   - AWS_PROFILE, DOCKER_HOST, other env vars
          -- Tradeoff: Adds ~200-500ms startup delay vs direct execution.
          -- Set to false only if you don't need environment or want faster startup.
          login_shell = true,
        },
      }
    end,
  },
  -- Look & Feel {{{
  "ellisonleao/gruvbox.nvim",
  "mhartington/formatter.nvim",
  "folke/todo-comments.nvim",
  "ryanoasis/vim-devicons",
  "xiyaowong/nvim-transparent",
  "bluz71/vim-moonfly-colors",
  "kdheepak/monochrome.nvim",
  "EdenEast/nightfox.nvim",
  "NLKNguyen/papercolor-theme",
  "folke/tokyonight.nvim",
  "rktjmp/lush.nvim",
  { "catppuccin/nvim", as = "catppuccin" },
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "kyazdani42/nvim-web-devicons", opt = true },
  },
  -- }}}
  -- LaTeX {{{
  {
    "lervag/vimtex",
    lazy = false, -- Load immediately for .tex files
    init = function()
      -- VimTeX configuration
      vim.g.vimtex_view_method = "zathura"
      vim.g.vimtex_compiler_method = "latexmk"

      -- Set local leader to backslash for VimTeX commands
      vim.g.maplocalleader = "\\"

      -- Disable overfull/underfull warnings
      vim.g.vimtex_quickfix_ignore_filters = {
        "Underfull",
        "Overfull",
      }

      -- Enable syntax concealment for a cleaner view
      vim.g.vimtex_syntax_conceal = {
        accents = 1,
        greek = 1,
        math_bounds = 0,
        math_delimiters = 1,
        math_fracs = 1,
        math_super_sub = 1,
        math_symbols = 1,
        sections = 0,
        styles = 1,
      }
    end,
  },
  -- }}}
  {
    "obsidian-nvim/obsidian.nvim",
    version = "*",
  },
}, {
  dev = {
    path = "/home/decoder/dev",
    patterns = {}, -- Empty means all plugins with dev = true use the dev path
    fallback = false,
  },
})
