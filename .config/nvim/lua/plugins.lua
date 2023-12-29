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
  use({
    "robitx/gp.nvim",
    config = function()
      require("gp").setup({
        agents = {
          -- Disable ChatGPT 3.5
          {
            name = "ChatGPT3-5",
            chat = false,    -- just name would suffice
            command = false, -- just name would suffice
          },
          {
            name = "ChatGPT4",
            chat = true,
            command = true,
            -- string with model name or table with model name and parameters
            model = { model = "gpt-4-1106-preview", temperature = 1.1, top_p = 1 },
            -- system prompt (use this to specify the persona/role of the AI)
            system_prompt = "You are a general AI assistant.\n\n"
                .. "The user provided the additional info about how they would like you to respond:\n\n"
                .. "- If you're unsure don't guess and say you don't know instead.\n"
                .. "- Ask question if you need clarification to provide better answer.\n"
                .. "- Think deeply and carefully from first principles step by step.\n"
                .. "- Zoom out first to see the big picture and then zoom in to details.\n"
                .. "- Use Socratic method to improve your thinking and coding skills.\n"
                .. "- Don't elide any code from your output if the answer requires coding.\n"
                .. "- Take a deep breath; You've got this!\n",
          },
        },
      })

      -- or setup with your own config (see Install > Configuration in Readme)
      -- require("gp").setup(conf)

      -- shortcuts might be setup here (see Usage > Shortcuts in Readme)
    end,
  })
  -- }}}
  -- Editor Extensions {{{
  use 'jesseleite/nvim-macroni'

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
      require("various-textobjs").setup { useDefaultKeymaps = true }
    end,
  }
  use({
    "wintermute-cell/gitignore.nvim",
    requires = {
      "nvim-telescope/telescope.nvim" -- optional: for multi-select
    }
  })
  use 'karoliskoncevicius/vim-sendtowindow'
  use { 'dccsillag/magma-nvim', run = ':UpdateRemotePlugins' }
  use "tpope/vim-rhubarb"
  use "David-Kunz/gen.nvim"
  use "RRethy/nvim-align"
  use "vim-scripts/scrollfix"
  use { "shortcuts/no-neck-pain.nvim", tag = "*" }
  use "stevearc/oil.nvim"
  use "echasnovski/mini.nvim"
  use "mattn/emmet-vim"
  use "mattn/webapi-vim"
  use "mhinz/vim-startify"
  use "wellle/targets.vim"
  use "preservim/nerdcommenter"
  use "tpope/vim-fugitive"
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
  use "ggandor/leap.nvim"
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
  use "kdheepak/lazygit.nvim"
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
  use { "nvim-treesitter/nvim-treesitter", run = ":TSUpdate" }
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
  use 'sbdchd/neoformat'
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
  use 'javiorfo/nvim-soil'

  -- Optional for puml syntax highlighting:
  use 'javiorfo/nvim-nyctophilia'
  use "weirongxu/plantuml-previewer.vim"
  -- }}}
  -- My Plugins {{{
  use "Piotr1215/yanksearch.nvim"
  -- }}}
  -- Look & Feel {{{
  use { "ellisonleao/gruvbox.nvim" }
  use { "ellisonleao/glow.nvim", branch = "main" }
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
  use "epwalsh/obsidian.nvim"
  if packer_bootstrap then
    require("packer").sync()
  end
end)
