return require('packer').startup(function()
  use 'wbthomason/packer.nvim'
-- Editor Functionality
  use 'easymotion/vim-easymotion'
  use 'mhinz/vim-startify'
  use 'vim-airline/vim-airline'
  use 'ryanoasis/vim-devicons'
  use {'junegunn/fzf', run = './install --bin' }
  use 'junegunn/fzf.vim'
  use 'ctrlpvim/ctrlp.vim'
  use 'nvim-lua/plenary.nvim'
  use { 'nvim-telescope/telescope.nvim', requires = { { 'nvim-lua/popup.nvim' }, { 'nvim-lua/plenary.nvim' } } }
  use {'nvim-telescope/telescope-fzf-native.nvim', run = 'make' }
  use 'voldikss/vim-floaterm'
  use 'rafamadriz/friendly-snippets'
  use 'cljoly/telescope-repo.nvim'
  use 'kdheepak/lazygit.nvim'
  use 'karoliskoncevicius/vim-sendtowindow'
  use 'jpalardy/vim-slime'
-- Editing Related
  use 'Raimondi/delimitMate'
  use 'godlygeek/tabular'
  use 'plasticboy/vim-markdown'
  use 'mattn/webapi-vim'
  use 'Yggdroot/indentLine'
  use 'tpope/vim-surround'
  use 'mattn/emmet-vim'
  use 'wellle/targets.vim'
  use 'vim-syntastic/syntastic'
  use 'sheerun/vim-polyglot'
  use({
        "iamcco/markdown-preview.nvim",
        run = ":call mkdp#util#install()",
        ft = { "markdown", "packer" },
  })
  use 'junegunn/vim-emoji'
  use 'christoomey/vim-system-copy'
  use 'dhruvasagar/vim-table-mode'
  use 'junegunn/limelight.vim'
  use 'ferrine/md-img-paste.vim'
  use 'SidOfc/mkdx'
  use 'weirongxu/plantuml-previewer.vim'
  use 'tyru/open-browser.vim'
  use 'dhruvasagar/vim-open-url'
  use 'hrsh7th/vim-vsnip'
  use 'hrsh7th/vim-vsnip-integ'
  use 'sakshamgupta05/vim-todo-highlight'
  use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }
  use 'preservim/nerdcommenter'
-- Programming
-- LSP
  -- LSP Client
  --use 'neovim/nvim-lspconfig'

  -- Language Server installer
  use {
    "williamboman/nvim-lsp-installer",
    {
        "neovim/nvim-lspconfig",
    }
  }
  -- Show VSCode-esque pictograms
  use 'onsails/lspkind-nvim'
  use {'tami5/lspsaga.nvim', requires = {'neovim/nvim-lspconfig'}}
    -- Autocompletion plugin
  use {
    'hrsh7th/nvim-cmp',
    requires = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-cmdline',
    }
  }

  -- snippets
  use {
    'hrsh7th/cmp-vsnip', requires = {
      'hrsh7th/vim-vsnip',
      'rafamadriz/friendly-snippets',
    }
  }
    -- Fancier statusline
  use {
    'nvim-lualine/lualine.nvim',
    requires = {
      'kyazdani42/nvim-web-devicons',
      'arkav/lualine-lsp-progress',
    },
  }
  use 'majutsushi/tagbar'
  use 'hashivim/vim-terraform'
  use 'fatih/vim-go'
  use {'neoclide/coc.nvim', branch = 'release'}
  use 'rhysd/vim-clang-format'
  use 'tpope/vim-fugitive'
  use 'airblade/vim-gitgutter'
-- Color Schemes
  use 'NLKNguyen/papercolor-theme'
  use "EdenEast/nightfox.nvim" -- Packer
  require('lualine').setup()
end)

