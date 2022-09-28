require('packer').startup(function(use)
  -- Packer
  use 'wbthomason/packer.nvim'
  -- Editor Extensions {{{
  use 'mattn/emmet-vim'
  use 'mattn/webapi-vim'
  use 'mhinz/vim-startify'
  use 'wellle/targets.vim'
  use 'preservim/nerdcommenter'
  use 'tpope/vim-fugitive'
  use 'voldikss/vim-floaterm'
  use 'sindrets/diffview.nvim'
  use 'ThePrimeagen/harpoon' -- https://github.com/ThePrimeagen/harpoon
  use 'kevinhwang91/rnvimr' -- https://github.com/kevinhwang91/rnvimr
  use 'airblade/vim-gitgutter'
  use({
    "kylechui/nvim-surround",
    config = function()
      require("nvim-surround").setup({})
    end
  })
  use 'folke/which-key.nvim'
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
  -- System Integration {{{
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
  use 'xiyaowong/telescope-emoji.nvim'
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
  use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }
  use { 'tami5/lspsaga.nvim', requires = { 'neovim/nvim-lspconfig' } }
  use 'onsails/lspkind-nvim'
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
  -- Snippets {{{
  use 'L3MON4D3/LuaSnip'
  use 'hrsh7th/vim-vsnip'
  use 'hrsh7th/vim-vsnip-integ'
  -- }}}
  -- Programming {{{
  use 'fatih/vim-go'
  use 'hashivim/vim-terraform'
  -- }}}
  -- Markdown {{{
  use 'jubnzv/mdeval.nvim'
  use 'tyru/open-browser.vim'
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
  use 'weirongxu/plantuml-previewer.vim'
  -- }}}
  -- Look & Feel {{{
  use { "ellisonleao/glow.nvim", branch = 'main' }
  use 'mhartington/formatter.nvim'
  use 'sakshamgupta05/vim-todo-highlight'
  use 'ryanoasis/vim-devicons'
  use 'xiyaowong/nvim-transparent'
  use 'bluz71/vim-moonfly-colors'
  use 'kdheepak/monochrome.nvim'
  use 'MunifTanjim/prettier.nvim'
  use 'EdenEast/nightfox.nvim'
  use 'NLKNguyen/papercolor-theme'
  use 'folke/tokyonight.nvim'
  use 'rktjmp/lush.nvim'
  use { "catppuccin/nvim", as = "catppuccin" }
  use 'vim-airline/vim-airline'
  -- }}}
end)
