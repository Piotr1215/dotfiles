require('packer').startup(function(use)
  -- Packer
  use 'wbthomason/packer.nvim'
  -- Git
  use { 'sindrets/diffview.nvim' }
  -- Editor Extensions {{{
  use 'ThePrimeagen/harpoon' -- https://github.com/ThePrimeagen/harpoon
  use 'kevinhwang91/rnvimr' -- https://github.com/kevinhwang91/rnvimr
  use 'airblade/vim-gitgutter'
  use { 'anuvyklack/hydra.nvim',
    requires = 'anuvyklack/keymap-layer.nvim' -- needed only for pink hydras
  }
  use {
    "folke/which-key.nvim",
    config = function()
      require("which-key").setup {
        plugins = {
          marks = true, -- shows a list of your marks on ' and `
          registers = true, -- shows your registers on " in NORMAL or <C-r> in INSERT mode
          spelling = {
            enabled = true, -- enabling this will show WhichKey when pressing z= to select spelling suggestions
            suggestions = 20, -- how many suggestions should be shown in the list?
          },
        }
      }
    end,
  }
  use 'lukas-reineke/indent-blankline.nvim'
  use 'machakann/vim-swap'
  use 'austintaylor/vim-commaobject'
  use 'easymotion/vim-easymotion'
  use 'ferrine/md-img-paste.vim'
  use {
    "cuducos/yaml.nvim",
    ft = { "yaml" }, -- optional
    requires = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-telescope/telescope.nvim" -- optional
    },
  }
  -- }}}
  -- File System Integration {{{
  use {
    'junegunn/fzf',
    run = './install --bin'
  }
  use 'junegunn/fzf.vim'
  use {
    'kyazdani42/nvim-tree.lua',
    requires = {
      'kyazdani42/nvim-web-devicons', -- optional, for file icon
    },
    tag = 'nightly' -- optional, updated every week. (see issue #1193)
  }
  -- }}}
  -- Telescope {{{
  use 'nvim-telescope/telescope-symbols.nvim'
  use 'cljoly/telescope-repo.nvim'
  use 'kdheepak/lazygit.nvim'
  use 'ctrlpvim/ctrlp.vim'
  use {
    'nvim-telescope/telescope.nvim',
    requires = {
      { 'nvim-lua/popup.nvim' },
      { 'nvim-lua/plenary.nvim' }
    }
  }
  use {
    'nvim-telescope/telescope-file-browser.nvim'
  }
  use {
    'nvim-telescope/telescope-fzf-native.nvim', run = 'make'
  }
  use { "smartpde/telescope-recent-files" }
  -- }}}
  -- LSP {{{
  use { "williamboman/mason.nvim" }
  use "williamboman/mason-lspconfig.nvim"
  use 'williamboman/nvim-lsp-installer'
  use "neovim/nvim-lspconfig"
  use 'mfussenegger/nvim-dap'
  use 'jose-elias-alvarez/null-ls.nvim'
  use {
    "folke/trouble.nvim",
    requires = "kyazdani42/nvim-web-devicons",
    config = function()
      require("trouble").setup {}
    end
  }
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
  use 'leoluz/nvim-dap-go'
  use {
    "rcarriga/nvim-dap-ui",
    requires = {
      "mfussenegger/nvim-dap"
    }
  }
  use 'theHamsta/nvim-dap-virtual-text'
  use 'nvim-telescope/telescope-dap.nvim'
  use "stevearc/dressing.nvim"
  -- }}}
  use 'L3MON4D3/LuaSnip'
  use 'hrsh7th/vim-vsnip'
  use 'hrsh7th/vim-vsnip-integ'
  use 'mattn/emmet-vim'
  use 'mattn/webapi-vim'
  use 'mhinz/vim-startify'
  -- Programming
  use 'fatih/vim-go'
  -- DevOps
  use 'hashivim/vim-terraform'
  use 'xiyaowong/telescope-emoji.nvim'
  -- Markdown {{{
  use 'jubnzv/mdeval.nvim'
  -- use 'Yggdroot/indentLine'
  use 'tyru/open-browser.vim'
  -- Fenced edit of markdown code blocks
  use {
    'AckslD/nvim-FeMaco.lua',
    config = 'require("femaco").setup()',
  }
  use 'ixru/nvim-markdown'
  use 'dhruvasagar/vim-open-url'
  use 'marcelofern/vale.nvim'
  use 'dhruvasagar/vim-table-mode'
  use 'renerocksai/telekasten.nvim'
  use({ "iamcco/markdown-preview.nvim",
    run = "cd app && npm install",
    setup = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    ft = { "markdown" }, })
  -- Look & Feel {{{
  use 'xiyaowong/nvim-transparent'
  use 'bluz71/vim-moonfly-colors'
  use 'kdheepak/monochrome.nvim'
  use 'MunifTanjim/prettier.nvim'
  use 'EdenEast/nightfox.nvim'
  use 'NLKNguyen/papercolor-theme'
  use 'folke/tokyonight.nvim'
  use 'rktjmp/lush.nvim'
  use { "catppuccin/nvim", as = "catppuccin" }
  -- }}}
  use { 'mhartington/formatter.nvim' }
  use 'vim-airline/vim-airline'
  use 'onsails/lspkind-nvim'
  use 'preservim/nerdcommenter'
  use 'Raimondi/delimitMate'
  use 'ryanoasis/vim-devicons'
  use 'sakshamgupta05/vim-todo-highlight'
  -- use 'sheerun/vim-polyglot'
  use { 'tami5/lspsaga.nvim', requires = { 'neovim/nvim-lspconfig' } }
  use 'tpope/vim-fugitive'
  use({
    "kylechui/nvim-surround",
    config = function()
      require("nvim-surround").setup({
        -- Configuration here, or leave empty to use defaults
      })
    end
  })
  use 'voldikss/vim-floaterm'
  use 'weirongxu/plantuml-previewer.vim'
  use 'wellle/targets.vim'
  use { "ellisonleao/glow.nvim", branch = 'main' }
  use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }
end)
