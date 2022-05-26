return require('packer').startup(function()
  use 'wbthomason/packer.nvim'
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
end)
