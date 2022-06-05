return require('packer').startup(function()
     -- Packer
     use 'wbthomason/packer.nvim'
     -- Git
     use 'airblade/vim-gitgutter'
     use 'cljoly/telescope-repo.nvim'
     use 'kdheepak/lazygit.nvim'
     -- Editor Extensions
     use 'easymotion/vim-easymotion'
     use 'ferrine/md-img-paste.vim'
     use 'hrsh7th/vim-vsnip'
     use 'hrsh7th/vim-vsnip-integ'
     use 'jpalardy/vim-slime'
     use 'junegunn/fzf.vim'
     use 'junegunn/vim-emoji'
     use {
          'kyazdani42/nvim-tree.lua',
          requires = {
               'kyazdani42/nvim-web-devicons', -- optional, for file icon
          },
          tag = 'nightly' -- optional, updated every week. (see issue #1193)
     }
     use {
          'junegunn/fzf',
          run = './install --bin'
     }
     use 'lukas-reineke/indent-blankline.nvim'
     use 'majutsushi/tagbar'
     use 'mattn/emmet-vim'
     use 'mattn/webapi-vim'
     use 'mhinz/vim-startify'
     use {
          'nvim-lualine/lualine.nvim',
          requires = {
               'kyazdani42/nvim-web-devicons',
               'arkav/lualine-lsp-progress', },
     }
     -- Programming
     use 'fatih/vim-go'
     -- DevOps
     use 'hashivim/vim-terraform'
     -- Telescope
     use 'christoomey/vim-system-copy'
     use 'ctrlpvim/ctrlp.vim'
     -- Debugging
     use 'mfussenegger/nvim-dap'
     use 'leoluz/nvim-dap-go'
     use {
          "rcarriga/nvim-dap-ui",
          requires = {
               "mfussenegger/nvim-dap" }
     }
     use 'theHamsta/nvim-dap-virtual-text'
     use 'nvim-telescope/telescope-dap.nvim'
     -- Markdown
     use({ "iamcco/markdown-preview.nvim",
          run = "cd app && npm install",
          setup = function()
               vim.g.mkdp_filetypes = { "markdown" }
          end,
          ft = { "markdown" }, })
     use 'rhysd/vim-grammarous'
     use 'dhruvasagar/vim-open-url'
     use 'dhruvasagar/vim-table-mode'
     use 'ferrine/md-img-paste.vim'
     use 'godlygeek/tabular'
     use 'plasticboy/vim-markdown'
     -- Look & Feel
     use 'EdenEast/nightfox.nvim'
     use 'NLKNguyen/papercolor-theme'
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
               'hrsh7th/cmp-cmdline', }
     }
     use {
          'ldelossa/gh.nvim',
          requires = {
               { 'ldelossa/litee.nvim' }
          }
     }
     use {
          'neoclide/coc.nvim',
          branch = 'release'
     }
     use 'nvim-lua/plenary.nvim'
     use {
          'nvim-telescope/telescope-file-browser.nvim'
     }
     use {
          'nvim-telescope/telescope-fzf-native.nvim', run = 'make'
     }
     use {
          'nvim-telescope/telescope.nvim',
          requires = {
               { 'nvim-lua/popup.nvim' },
               { 'nvim-lua/plenary.nvim' }
          }
     }
     use 'onsails/lspkind-nvim'
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
     use { "ellisonleao/glow.nvim", branch = 'main' }
     use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }
end)
