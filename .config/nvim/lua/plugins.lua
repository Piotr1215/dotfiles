return require('packer').startup(function(use)
  -- Packer
  use 'wbthomason/packer.nvim'
  -- Editor Extensions {{{
  use {
    "windwp/nvim-autopairs",
    config = function() require("nvim-autopairs").setup {} end
  }
  use 'vim-scripts/scrollfix'
  use {"shortcuts/no-neck-pain.nvim", tag = "*" } 
  use 'stevearc/oil.nvim'
  use 'echasnovski/mini.nvim'
  use 'sheerun/vim-polyglot'
  use 'mattn/emmet-vim'
  use 'mattn/webapi-vim'
  use 'mhinz/vim-startify'
  use 'wellle/targets.vim'
  use 'preservim/nerdcommenter'
  use 'tpope/vim-fugitive'
  use 'voldikss/vim-floaterm'
  use 'sindrets/diffview.nvim'
  use 'ThePrimeagen/harpoon'
  use 'kevinhwang91/rnvimr'
  use 'airblade/vim-gitgutter'
  use({
    "kylechui/nvim-surround",
    config = function()
      require("nvim-surround").setup({})
    end
  })
  use 'gcmt/taboo.vim'
  use 'folke/which-key.nvim'
  use 'lukas-reineke/indent-blankline.nvim'
  use 'machakann/vim-swap'
  use 'austintaylor/vim-commaobject'
  use 'ferrine/md-img-paste.vim'
  use {
    "cuducos/yaml.nvim",
    ft = { "yaml" }, -- optional
    requires = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-telescope/telescope.nvim" -- optional
    },
  }
  -- use 'https://gitlab.com/madyanov/svart.nvim'
  use 'ggandor/leap.nvim'
  use { 'kevinhwang91/nvim-bqf' }
  -- }}}
  -- System Integration {{{
  use {
    'junegunn/fzf',
    run = './install --bin'
  }
  use 'junegunn/fzf.vim'
  use {
    'nvim-tree/nvim-tree.lua',
    requires = {
      'nvim-tree/nvim-web-devicons', -- optional, for file icon
    },
    tag = 'nightly' -- optional, updated every week. (see issue #1193)
  }
  -- }}}
  -- Telescope {{{
  use 'danielpieper/telescope-tmuxinator.nvim'
  use 'jvgrootveld/telescope-zoxide'
  use {
    'dhruvmanila/telescope-bookmarks.nvim',
    tag = '*',
    -- Uncomment if the selected browser is Firefox, Waterfox or buku
    -- requires = {
    --   'kkharji/sqlite.lua',
    -- }
  }
  use 'xiyaowong/telescope-emoji.nvim'
  use 'nvim-telescope/telescope-symbols.nvim'
  use 'cljoly/telescope-repo.nvim'
  use 'kdheepak/lazygit.nvim'
  use {
    'nvim-telescope/telescope.nvim',
    requires = {
      { 'nvim-lua/popup.nvim' },
      { 'nvim-lua/plenary.nvim' },
      { "nvim-telescope/telescope-live-grep-args.nvim" },
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
  use { 'ibhagwan/fzf-lua' }
  use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }
  use { 'tami5/lspsaga.nvim', requires = { 'neovim/nvim-lspconfig' } }
  use 'onsails/lspkind-nvim'
  use { "williamboman/mason.nvim" }
  use 'williamboman/mason-lspconfig.nvim'
  use "neovim/nvim-lspconfig"
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
  -- use 'nvim-telescope/telescope-dap.nvim'
  use "stevearc/dressing.nvim"
  -- }}}
  -- Snippets {{{
  use 'L3MON4D3/LuaSnip'
  use 'hrsh7th/vim-vsnip'
  use 'hrsh7th/vim-vsnip-integ'
  -- }}}
  -- Programming {{{
  use {
    'saecki/crates.nvim',
    requires = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('crates').setup()
    end,
  }
  use 'simrat39/rust-tools.nvim'
  use 'IndianBoy42/tree-sitter-just'
  use 'NoahTheDuke/vim-just'
  use 'fatih/vim-go'
  use 'hashivim/vim-terraform'
  use 'nvim-treesitter/nvim-treesitter-textobjects'
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
  use { "ellisonleao/gruvbox.nvim" }
  use 'uga-rosa/ccc.nvim'
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
  use {
    'nvim-lualine/lualine.nvim',
    requires = { 'kyazdani42/nvim-web-devicons', opt = true }
  }
  -- }}}
  use 'epwalsh/obsidian.nvim'
end)
