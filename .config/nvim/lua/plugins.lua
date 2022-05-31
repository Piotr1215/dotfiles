return require('packer').startup(function()
     use 'wbthomason/packer.nvim'
     use 'airblade/vim-gitgutter'
     use 'christoomey/vim-system-copy'
     use 'cljoly/telescope-repo.nvim'
     use 'ctrlpvim/ctrlp.vim'
     use 'dhruvasagar/vim-open-url'
     use 'dhruvasagar/vim-table-mode'
     use 'easymotion/vim-easymotion'
     use 'EdenEast/nightfox.nvim'
     use 'fatih/vim-go'
     use 'ferrine/md-img-paste.vim'
     use 'godlygeek/tabular'
     use 'hashivim/vim-terraform'
     use { 'hrsh7th/cmp-vsnip', requires = { 'hrsh7th/vim-vsnip', 'rafamadriz/friendly-snippets', } }
     use { 'hrsh7th/nvim-cmp', requires = { 'nvim-treesitter', 'hrsh7th/cmp-nvim-lsp', 'hrsh7th/cmp-buffer', 'hrsh7th/cmp-path', 'hrsh7th/cmp-cmdline', } }
     use 'hrsh7th/vim-vsnip'
     use 'hrsh7th/vim-vsnip-integ'
     use 'jpalardy/vim-slime'
     use { 'junegunn/fzf', run = './install --bin' }
     use 'junegunn/fzf.vim'
     use 'junegunn/vim-emoji'
     use 'kdheepak/lazygit.nvim'
     use {
          'kyazdani42/nvim-tree.lua',
          requires = {
               'kyazdani42/nvim-web-devicons', -- optional, for file icon
          },
          tag = 'nightly' -- optional, updated every week. (see issue #1193)
     }
     use { 'ldelossa/gh.nvim', requires = { { 'ldelossa/litee.nvim' } } }
     use 'lukas-reineke/indent-blankline.nvim'
     use 'majutsushi/tagbar'
     use 'mattn/emmet-vim'
     use 'mattn/webapi-vim'
     use 'mhinz/vim-startify'
     use { 'neoclide/coc.nvim', branch = 'release' }
     use 'NLKNguyen/papercolor-theme'
     use { 'nvim-lualine/lualine.nvim', requires = { 'kyazdani42/nvim-web-devicons', 'arkav/lualine-lsp-progress', }, }
     use 'nvim-lua/plenary.nvim'
     use { 'nvim-telescope/telescope-file-browser.nvim' }
     use { 'nvim-telescope/telescope-fzf-native.nvim', run = 'make' }
     use { 'nvim-telescope/telescope.nvim', requires = { { 'nvim-lua/popup.nvim' }, { 'nvim-lua/plenary.nvim' } } }
     use 'onsails/lspkind-nvim'
     use 'plasticboy/vim-markdown'
     use 'preservim/nerdcommenter'
     use 'Raimondi/delimitMate'
     use 'rhysd/vim-clang-format'
     use 'ryanoasis/vim-devicons'
     use 'sakshamgupta05/vim-todo-highlight'
     use 'sheerun/vim-polyglot'
     use { 'tami5/lspsaga.nvim', requires = { 'neovim/nvim-lspconfig' } }
     use 'tpope/vim-fugitive'
     use 'tpope/vim-surround'
     use 'tyru/open-browser.vim'
     use 'vim-syntastic/syntastic'
     use 'voldikss/vim-floaterm'
     use 'weirongxu/plantuml-previewer.vim'
     use 'wellle/targets.vim'
     use { 'williamboman/nvim-lsp-installer', { 'neovim/nvim-lspconfig', } }
     use 'Yggdroot/indentLine'
     use({ 'iamcco/markdown-preview.nvim', run = ':call mkdp#util#install()', ft = { 'markdown', 'packer' }, })
     use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }
end)
