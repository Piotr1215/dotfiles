local ensure_packer = function()
  local fn = vim.fn
  local install_path = fn.stdpath "data" .. "/site/pack/packer/start/packer.nvim"
  if fn.empty(fn.glob(install_path)) > 0 then
    fn.system { "git", "clone", "--depth", "1", "https://github.com/wbthomason/packer.nvim", install_path }
    vim.cmd [[packadd packer.nvim]]
    return true
  end
  return false
end

local packer_bootstrap = ensure_packer()
return require("packer").startup(function(use)
  -- Packer
  use "wbthomason/packer.nvim"
  -- AI {{{
  use "github/copilot.vim"
  use { "robitx/gp.nvim" }
  use { "MunifTanjim/nui.nvim" }
  use {
    "https://git.sr.ht/~whynothugo/lsp_lines.nvim",
    config = function()
      require("lsp_lines").setup()
    end,
  }
  use {
    "jellydn/hurl.nvim",
  }
  use {
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
  }

  -- }}}
  -- Editor Extensions {{{
  use "jesseleite/nvim-macroni"
  use "nosduco/remote-sshfs.nvim"

  use {
    "windwp/nvim-autopairs",
    config = function()
      require("nvim-autopairs").setup {}
    end,
  }
  use { "jonarrien/telescope-cmdline.nvim" }
  use {
    "chrisgrieser/nvim-various-textobjs",
    config = function()
      require("various-textobjs").setup { useDefaultKeymaps = false }
    end,
  }
  use "lewis6991/gitsigns.nvim"
  use {
    "wintermute-cell/gitignore.nvim",
    requires = {
      "nvim-telescope/telescope.nvim", -- optional: for multi-select
    },
  }
  use {
    "bloznelis/before.nvim",
    config = function()
      local before = require "before"
      before.setup()

      -- Jump to previous entry in the edit history
      vim.keymap.set("n", "<C-h>", before.jump_to_last_edit, {})

      -- Jump to next entry in the edit history
      vim.keymap.set("n", "<C-l>", before.jump_to_next_edit, {})

      -- Look for previous edits in telescope (needs telescope, obviously)
      vim.keymap.set("n", "<leader>oe", before.show_edits_in_telescope, {})
    end,
  }
  use { "ionide/Ionide-vim" }
  use "rcarriga/nvim-notify"
  use { "marcelofern/vale.nvim" }
  use "tyru/open-browser.vim"
  use "karoliskoncevicius/vim-sendtowindow"
  use { "dccsillag/magma-nvim", run = ":UpdateRemotePlugins" }
  use "tpope/vim-rhubarb"
  use { "nvim-neotest/nvim-nio" }
  use "David-Kunz/gen.nvim"
  use "RRethy/nvim-align"
  use "vim-scripts/scrollfix"
  use "stevearc/oil.nvim"
  use "echasnovski/mini.nvim"
  use "mattn/emmet-vim"
  use "mattn/webapi-vim"
  use "mhinz/vim-startify"
  use "preservim/nerdcommenter"
  use "tpope/vim-fugitive"
  use "folke/neodev.nvim"
  use "Piotr1215/telescope-crossplane.nvim"
  use { "mistricky/codesnap.nvim", run = "make" }
  use {
    "jiaoshijie/undotree",
    config = function()
      require("undotree").setup()
    end,
    requires = {
      "nvim-lua/plenary.nvim",
    },
  }
  use "voldikss/vim-floaterm"
  use {
    "kylechui/nvim-surround",
    config = function()
      require("nvim-surround").setup {}
    end,
  }
  use "folke/which-key.nvim"
  use "lukas-reineke/indent-blankline.nvim"
  use "machakann/vim-swap"
  use "austintaylor/vim-commaobject"
  use "ferrine/md-img-paste.vim"
  use {
    "cuducos/yaml.nvim",
    ft = { "yaml" }, -- optional
    requires = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-telescope/telescope.nvim", -- optional
    },
  }
  -- use 'https://gitlab.com/madyanov/svart.nvim'
  use { "kevinhwang91/nvim-bqf" } -- better quickfix window
  -- }}}
  -- System Integration {{{
  use {
    "junegunn/fzf",
    run = "./install --bin",
  }
  use "junegunn/fzf.vim"
  use "nvim-tree/nvim-web-devicons" -- optional, for file icon
  -- }}}
  -- Telescope {{{
  use "danielpieper/telescope-tmuxinator.nvim"
  use "jvgrootveld/telescope-zoxide"
  use {
    "ellisonleao/glow.nvim",
    config = function()
      require("glow").setup()
    end,
  }
  use {
    "dhruvmanila/telescope-bookmarks.nvim",
    tag = "*",
    -- Uncomment if the selected browser is Firefox, Waterfox or buku
    -- requires = {
    --   'kkharji/sqlite.lua',
    -- }
  }
  use "xiyaowong/telescope-emoji.nvim"
  use "nvim-telescope/telescope-symbols.nvim"
  use "cljoly/telescope-repo.nvim"
  use {
    "nvim-telescope/telescope.nvim",
    requires = {
      { "nvim-lua/popup.nvim" },
      { "nvim-lua/plenary.nvim" },
      { "nvim-telescope/telescope-live-grep-args.nvim" },
    },
  }
  use {
    "nvim-telescope/telescope-file-browser.nvim",
  }
  use {
    "nvim-telescope/telescope-fzf-native.nvim",
    run = "make",
  }
  use { "smartpde/telescope-recent-files" }
  -- }}}
  -- LSP {{{
  use "ray-x/lsp_signature.nvim"
  use { "ibhagwan/fzf-lua" }
  use { "nvim-treesitter/nvim-treesitter", run = ":TSUpdate", requires = { "nvim-treesitter/playground" } }
  use { "tami5/lspsaga.nvim", requires = { "neovim/nvim-lspconfig" } }
  use "onsails/lspkind-nvim"
  use { "williamboman/mason.nvim" }
  use "williamboman/mason-lspconfig.nvim"
  use "neovim/nvim-lspconfig"
  use {
    "folke/trouble.nvim",
    requires = "kyazdani42/nvim-web-devicons",
    config = function()
      require("trouble").setup {}
    end,
  }
  use "hrsh7th/cmp-nvim-lsp-signature-help"
  use {
    "hrsh7th/cmp-vsnip",
    requires = {
      "hrsh7th/vim-vsnip",
      "rafamadriz/friendly-snippets",
    },
  }
  use { "shortcuts/no-neck-pain.nvim", tag = "*" }

  use "leoluz/nvim-dap-go"
  use {
    "rcarriga/nvim-dap-ui",
    requires = {
      "mfussenegger/nvim-dap",
    },
  }
  use "mfussenegger/nvim-dap-python"
  -- }}}
  -- Snippets {{{
  use {
    "hrsh7th/nvim-cmp",
    requires = {
      "nvim-treesitter",
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
    },
  }
  use "hrsh7th/cmp-nvim-lua"
  use "hrsh7th/vim-vsnip"
  use "hrsh7th/vim-vsnip-integ"
  -- }}}
  -- Programming {{{
  use "theHamsta/nvim-dap-virtual-text"
  use "stevearc/dressing.nvim"
  use {
    "saecki/crates.nvim",
    requires = { "nvim-lua/plenary.nvim" },
    config = function()
      require("crates").setup()
    end,
  }
  use "simrat39/rust-tools.nvim"
  use "IndianBoy42/tree-sitter-just"
  use "NoahTheDuke/vim-just"
  use "ray-x/go.nvim"
  use "ray-x/guihua.lua" -- recommended if need floating window support
  use "rmagatti/goto-preview"
  use "nvim-treesitter/nvim-treesitter-textobjects"
  -- }}}
  -- Markdown {{{
  use "jubnzv/mdeval.nvim"
  use {
    "AckslD/nvim-FeMaco.lua",
    config = 'require("femaco").setup()',
  }
  use "sbdchd/neoformat"
  use "ixru/nvim-markdown"
  use "dhruvasagar/vim-open-url"
  use {
    "iamcco/markdown-preview.nvim",
    run = "cd app && npm install",
    setup = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    ft = { "markdown" },
  }
  use "javiorfo/nvim-soil"

  -- Optional for puml syntax highlighting:
  use "javiorfo/nvim-nyctophilia"
  use "weirongxu/plantuml-previewer.vim"
  -- }}}
  -- My Plugins {{{
  use "Piotr1215/yanksearch.nvim"
  -- }}}
  -- Look & Feel {{{
  use { "ellisonleao/gruvbox.nvim" }
  use "mhartington/formatter.nvim"
  use "folke/todo-comments.nvim"
  use "ryanoasis/vim-devicons"
  use "xiyaowong/nvim-transparent"
  use "bluz71/vim-moonfly-colors"
  use "kdheepak/monochrome.nvim"
  use "EdenEast/nightfox.nvim"
  use "NLKNguyen/papercolor-theme"
  use "folke/tokyonight.nvim"
  use "rktjmp/lush.nvim"
  use { "catppuccin/nvim", as = "catppuccin" }
  use {
    "nvim-lualine/lualine.nvim",
    requires = { "kyazdani42/nvim-web-devicons", opt = true },
  }
  -- }}}
  use {
    "epwalsh/obsidian.nvim",
    tag = "*",
  }
  if packer_bootstrap then
    require("packer").sync()
  end
end)
