package.path = package.path .. ";" .. vim.fn.expand "$HOME" .. "/.luarocks/share/lua/5.1/?/init.lua"
package.path = package.path .. ";" .. vim.fn.expand "$HOME" .. "/.luarocks/share/lua/5.1/?.lua"
-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
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
  "robitx/gp.nvim",
  "MunifTanjim/nui.nvim",
  {
    "jellydn/hurl.nvim",
  },
  {
    "Piotr1215/toggler.nvim",
    config = function()
      require("toggler").setup {
        {
          name = "Vale",
          cmd = "Vale",
          key = "<leader>vl",
          pattern = "*.md",
        },
      }
    end,
  },

  -- }}}
  -- Editor Extensions {{{
  "romainl/vim-cool",
  "yssl/QFEnter",
  "jesseleite/nvim-macroni",
  "3rd/image.nvim",
  "nosduco/remote-sshfs.nvim",
  "nvim-neotest/neotest-python",
  "nvim-neotest/neotest-plenary",
  {
    "windwp/nvim-autopairs",
    config = function()
      require("nvim-autopairs").setup {}
    end,
  },
  "jonarrien/telescope-cmdline.nvim",
  {
    "chrisgrieser/nvim-various-textobjs",
    config = function()
      require("various-textobjs").setup { useDefaultKeymaps = false }
    end,
  },
  {
    "wintermute-cell/gitignore.nvim",
    dependencies = {
      "nvim-telescope/telescope.nvim", -- optional: for multi-select
    },
  },
  "ionide/Ionide-vim",
  "rcarriga/nvim-notify",
  "marcelofern/vale.nvim",
  "tyru/open-browser.vim",
  "karoliskoncevicius/vim-sendtowindow",
  "tpope/vim-rhubarb",
  "nvim-neotest/nvim-nio",
  "David-Kunz/gen.nvim",
  "RRethy/nvim-align",
  "vim-scripts/scrollfix",
  "echasnovski/mini.nvim",
  "mattn/emmet-vim",
  "mattn/webapi-vim",
  "mhinz/vim-startify",
  "preservim/nerdcommenter",
  "tpope/vim-fugitive",
  "Piotr1215/telescope-crossplane.nvim",
  {
    "jiaoshijie/undotree",
    config = function()
      require("undotree").setup()
    end,
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
  },
  "voldikss/vim-floaterm",
  {
    "kylechui/nvim-surround",
    config = function()
      require("nvim-surround").setup {}
    end,
  },
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
  {
    "ellisonleao/glow.nvim",
    config = function()
      require("glow").setup()
    end,
  },
  {
    "dhruvmanila/telescope-bookmarks.nvim",
    version = "*",
    -- Uncomment if the selected browser is Firefox, Waterfox or buku
    -- dependencies = {
    --   'kkharji/sqlite.lua',
    -- }
  },
  "xiyaowong/telescope-emoji.nvim",
  "nvim-telescope/telescope-symbols.nvim",
  "cljoly/telescope-repo.nvim",
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      { "nvim-lua/popup.nvim" },
      { "nvim-lua/plenary.nvim" },
      { "nvim-telescope/telescope-live-grep-args.nvim" },
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
  { "tami5/lspsaga.nvim", dependencies = { "neovim/nvim-lspconfig" } },
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
  {
    "folke/trouble.nvim",
    dependencies = "kyazdani42/nvim-web-devicons",
    config = function()
      require("trouble").setup {}
    end,
  },
  "hrsh7th/cmp-nvim-lsp-signature-help",
  {
    "hrsh7th/cmp-vsnip",
    dependencies = {
      "hrsh7th/vim-vsnip",
      "rafamadriz/friendly-snippets",
    },
  },
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
      "nvim-lua/plenary.nvim",
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
  "hrsh7th/vim-vsnip",
  "hrsh7th/vim-vsnip-integ",
  -- }}}
  -- Programming {{{
  "theHamsta/nvim-dap-virtual-text",
  "stevearc/dressing.nvim",
  {
    "saecki/crates.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("crates").setup()
    end,
  },
  "simrat39/rust-tools.nvim",
  "IndianBoy42/tree-sitter-just",
  "NoahTheDuke/vim-just",
  "ray-x/go.nvim",
  "ray-x/guihua.lua", -- recommended if need floating window support
  "rmagatti/goto-preview",
  "nvim-treesitter/nvim-treesitter-textobjects",
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
  "Piotr1215/yanksearch.nvim",
  "Piotr1215/typeit.nvim",
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
    "epwalsh/obsidian.nvim",
    version = "*",
  },
}
