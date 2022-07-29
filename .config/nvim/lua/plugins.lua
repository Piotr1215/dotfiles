return require('packer').startup(function()
     -- Packer
     use 'wbthomason/packer.nvim'
     -- Git
     use 'alaviss/nim.nvim'
     use 'airblade/vim-gitgutter'
     use 'cljoly/telescope-repo.nvim'
     use 'kdheepak/lazygit.nvim'
     -- Editor Extensions
     use "stevearc/dressing.nvim"
     use({
          "ziontee113/icon-picker.nvim",
          config = function()
               require("icon-picker")
          end,
     })
     use { 'anuvyklack/hydra.nvim',
          requires = 'anuvyklack/keymap-layer.nvim' -- needed only for pink hydras
     }
     use {
          "folke/which-key.nvim",
          config = function()
               require("which-key").setup {
                    -- your configuration comes here
                    -- or leave it empty to use the default settings
                    -- refer to the configuration section below
               }
          end
     }
     use 'vimpostor/vim-tpipeline'
     use 'famiu/nvim-reload'
     use 'easymotion/vim-easymotion'
     use 'ferrine/md-img-paste.vim'
     use 'L3MON4D3/LuaSnip'
     use 'hrsh7th/vim-vsnip'
     use 'hrsh7th/vim-vsnip-integ'
     use 'jpalardy/vim-slime'
     use 'junegunn/fzf.vim'
     use 'nvim-telescope/telescope-symbols.nvim'
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
     use {
          "folke/zen-mode.nvim",
          config = function()
               require("zen-mode").setup {
               }
          end
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
     -- Lua
     use {
          "ahmedkhalf/project.nvim",
          config = function()
               require("project_nvim").setup {
                    -- your configuration comes here
                    -- or leave it empty to use the default settings
                    -- refer to the configuration section below
               }
          end
     }
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
     use 'renerocksai/telekasten.nvim'
     use 'SidOfc/mkdx'
     use({ "iamcco/markdown-preview.nvim",
          run = "cd app && npm install",
          setup = function()
               vim.g.mkdp_filetypes = { "markdown" }
          end,
          ft = { "markdown" }, })
     use 'dhruvasagar/vim-open-url'
     use 'marcelofern/vale.nvim'
     use 'jose-elias-alvarez/null-ls.nvim'
     use {
          "folke/trouble.nvim",
          requires = "kyazdani42/nvim-web-devicons",
          config = function()
               require("trouble").setup {
                    -- your configuration comes here
                    -- or leave it empty to use the default settings
                    -- refer to the configuration section below
               }
          end
     }
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
     use {'neoclide/coc.nvim', branch = 'release'}
     use { 'mhartington/formatter.nvim' }
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
