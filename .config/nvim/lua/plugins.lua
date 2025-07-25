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

return require("lazy").setup {
  -- AI {{{
  "github/copilot.vim",
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "main",
    dependencies = {
      { "github/copilot.vim" },
      { "nvim-lua/plenary.nvim" },
    },
    build = "make tiktoken",
    opts = {
      -- NOTE: The model can be changed depending on your GitHub Copilot Chat settings.
      -- Supported models include Claude, GPT-4, and others if enabled in your GitHub account.
      model = "claude-3.5-sonnet", -- Default to Claude
      window = {
        layout = "vertical",
        width = 0.4,
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
  { "windwp/nvim-autopairs", opts = {} },
  "jonarrien/telescope-cmdline.nvim",
  { "chrisgrieser/nvim-various-textobjs", opts = {} },
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
  "neovim/nvim-lspconfig",
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
  "simrat39/rust-tools.nvim",
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
    dependencies = {
      "nvim-telescope/telescope.nvim",
    },
  },
  -- }}}
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
  {
    "obsidian-nvim/obsidian.nvim",
    version = "*",
  },
}
