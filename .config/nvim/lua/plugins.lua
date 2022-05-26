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
  use 'nvim-telescope/telescope.nvim'
  use {'nvim-telescope/telescope-fzf-native.nvim', run = 'make' }
  use 'voldikss/vim-floaterm'
  use 'rafamadriz/friendly-snippets'
  use 'cljoly/telescope-repo.nvim'
  use 'kdheepak/lazygit.nvim'
  use 'karoliskoncevicius/vim-sendtowindow'
  use 'jpalardy/vim-slime'
  use { 'ldelossa/gh.nvim' requires = { { 'ldelossa/litee.nvim' } } }
end)

