local ensure_packer = function()
  local fn = vim.fn
  local install_path = fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'
  if fn.empty(fn.glob(install_path)) > 0 then
    fn.system({ 'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path })
    vim.cmd [[packadd packer.nvim]]
    return true
  end
  return false
end

local packer_bootstrap = ensure_packer()
return require('packer').startup(function(use)
  -- Packer
  use 'wbthomason/packer.nvim'
  -- AI {{{
  use 'github/copilot.vim'
  use({
    "jackMort/ChatGPT.nvim",
    config = function()
      require("chatgpt").setup({
        chat = {
          welcome_message = "Welcome to ChatGPT.nvim!",
          keymaps = {
            yank_last = "<C-y>",
            yank_last_code = "<C-k>",
            scroll_up = "<C-u>",
            scroll_down = "<C-d>",
            toggle_settings = "<C-o>",
            new_session = "<C-n>",
            cycle_windows = "<Tab>",
            -- in the Sessions pane
            select_session = "<Space>",
            rename_session = "r",
            delete_session = "d",
          },
        },
        popup_input = {
          submit = "<C-s>",
        },
        openai_params = {
          model = "gpt-4",
          frequency_penalty = 0,
          presence_penalty = 0,
          max_tokens = 300,
          temperature = 0.5,
          top_p = 1,
          n = 1,
        },
        openai_edit_params = {
          model = "code-davinci-edit-001",
          temperature = 0,
          top_p = 1,
          n = 1,
        },
        actions_paths = { "~/.config/chatgpt/actions.json" },
      })
    end,
    requires = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim"
    }
  })
  -- }}}
  -- Editor Extensions {{{
  use {
    "windwp/nvim-autopairs",
    config = function() require("nvim-autopairs").setup {} end
  }
  use { 'jonarrien/telescope-cmdline.nvim' }
  use {
    "chrisgrieser/nvim-various-textobjs",
    config = function()
      require("various-textobjs").setup({ useDefaultKeymaps = true })
    end,
  }
  use 'ThePrimeagen/harpoon'
  use 'RRethy/nvim-align'
  use 'vim-scripts/scrollfix'
  use { "shortcuts/no-neck-pain.nvim", tag = "*" }
  use 'stevearc/oil.nvim'
  use 'echasnovski/mini.nvim'
  use 'mattn/emmet-vim'
  use 'mattn/webapi-vim'
  use 'mhinz/vim-startify'
  use 'wellle/targets.vim'
  use 'preservim/nerdcommenter'
  use 'tpope/vim-fugitive'
  use 'voldikss/vim-floaterm'
  use 'sindrets/diffview.nvim'
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
  use { 'kevinhwang91/nvim-bqf' } -- better quickfix window
  -- }}}
  -- System Integration {{{
  use {
    'junegunn/fzf',
    run = './install --bin'
  }
  use 'junegunn/fzf.vim'
  use 'nvim-tree/nvim-web-devicons' -- optional, for file icon
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
  use 'ray-x/lsp_signature.nvim'
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
  use 'leoluz/nvim-dap-go'
  use {
    "rcarriga/nvim-dap-ui",
    requires = {
      "mfussenegger/nvim-dap"
    }
  }
  use 'mfussenegger/nvim-dap-python'
  -- }}}
  -- Snippets {{{
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
  use 'L3MON4D3/LuaSnip'
  use 'hrsh7th/vim-vsnip'
  use 'hrsh7th/vim-vsnip-integ'
  -- }}}
  -- Programming {{{
  use 'theHamsta/nvim-dap-virtual-text'
  use "stevearc/dressing.nvim"
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
  use 'ray-x/go.nvim'
  use 'ray-x/guihua.lua' -- recommended if need floating window support
  use 'rmagatti/goto-preview'
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
  use({
    "iamcco/markdown-preview.nvim",
    run = "cd app && npm install",
    setup = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    ft = { "markdown" },
  })
  use 'weirongxu/plantuml-previewer.vim'
  -- }}}
  -- Look & Feel {{{
  use { "ellisonleao/gruvbox.nvim" }
  use 'uga-rosa/ccc.nvim'
  use { "ellisonleao/glow.nvim", branch = 'main' }
  use 'mhartington/formatter.nvim'
  use 'folke/todo-comments.nvim'
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
  if packer_bootstrap then
    require('packer').sync()
  end
end)
