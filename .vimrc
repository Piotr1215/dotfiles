set nocompatible              " be iMproved, required
filetype off                  " required

set ignorecase
set smartcase
set hidden
set noerrorbells
set scrolloff=8
set signcolumn=yes

" custom setting
set clipboard=unnamed " use system clipboard
set mouse=v
set number
set encoding=utf-8
set backspace=indent,eol,start
set cursorline
set guioptions=

" indent for global
set expandtab
set shiftwidth=4
set softtabstop=4
set autoindent
set relativenumber

syntax on
syntax enable
" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim

" Custom shortcuts
nmap <F8> :TagbarToggle<CR>
nnoremap ,<space> :nohlsearch<CR>
" Copy line from above and inser under cursor and enter inser mode from the
" start of the line
nnoremap <Leader>c 1ky$jp0i
nnoremap <Leader>ok A :+1: <esc><CR>

"map <Leader>k ":+1:" <esc>
"map <Leader>k obinding.pry<ESC>

call vundle#begin()
" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'

" all plugin
Plugin 'mhinz/vim-startify'
Plugin 'Valloric/YouCompleteMe'
Plugin 'vim-syntastic/syntastic'

Plugin 'fatih/vim-go'

Plugin 'scrooloose/nerdtree'
Plugin 'vim-airline/vim-airline'
Plugin 'Raimondi/delimitMate'

" Automatic closing of brackets matching
" Plugin 'morhetz/gruvbox'

" F8 shortcut
Plugin 'majutsushi/tagbar'

Plugin 'Yggdroot/indentLine'

Plugin 'hashivim/vim-terraform'

Plugin 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plugin 'junegunn/fzf.vim'

Plugin 'terryma/vim-multiple-cursors'

Plugin 'tpope/vim-surround'
Plugin 'mattn/emmet-vim'

Plugin 'dense-analysis/ale'
Plugin 'sheerun/vim-polyglot'
Plugin 'joshdick/onedark.vim'

Plugin 'christoomey/vim-system-copy'

" All of your Plugins must be added before the following line
call vundle#end()            " required
filetype plugin indent on    " required

colorscheme onedark

" indent for special file
autocmd FileType c,cpp setlocal expandtab shiftwidth=2 softtabstop=2 cindent
autocmd FileType python setlocal expandtab shiftwidth=4 softtabstop=4 autoindent
autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab

" setup for ycm
let g:ycm_global_ycm_extra_conf = '~/.vim/bundle/YouCompleteMe/third_party/ycmd/examples/.ycm_extra_conf.py'
let g:ycm_python_binary_path = 'python'
let g:ycm_complete_in_comments = 1
let g:ycm_autoclose_preview_window_after_completion = 1
let g:ycm_autoclose_preview_window_after_insertion = 1
let g:ycm_semantic_triggers =  {
  \ 'c' : ['re!\w{2}'],
  \ 'cpp' : ['re!\w{2}'],
  \ 'python' : ['re!\w{2}'],
  \ }

" setup for syntastic
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
let g:syntastic_always_populate_loc_list = 0
let g:syntastic_auto_loc_list = 0
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 0
let g:syntastic_python_checkers = ['flake8']

" setup for terraform
let g:terraform_fmt_on_save=1
let g:terraform_align=1

" autoformat
augroup autoformat_settings
  autocmd FileType c,cpp,proto,javascript AutoFormatBuffer clang-format
  autocmd FileType python AutoFormatBuffer yapf
augroup END

" open NERDTree automatically when vim starts up on opening a directory
let NERDTreeShowHidden=1
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists("s:std_in") | exe 'NERDTree' argv()[0] | wincmd p | ene | endif

map <silent> <F5> : NERDTreeToggle<CR>
map ; :Files<CR>

" setup for gruvbox
" set t_Co=256
" set background=dark
" colorscheme industry
" let g:gruvbox_contrast_dark = 'soft'

" setup for ctrlp
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlP'
let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_custom_ignore = '\v[\/]\.(git|hg|svn)$'
let g:ctrlp_custom_ignore = {
  \ 'dir':  '\v[\/]\.(git|hg|svn)$',
  \ 'file': '\v\.(exe|so|dll)$',
  \ 'link': 'some_bad_symbolic_links',
  \ }
set wildignore+=*/tmp/*,*.so,*.swp,*.zip


" setup for indent line
let g:indentLine_char = '│'
set tags=./tags,tags;$HOME
"source ~/cscope_maps.vim

let g:go_fmt_command = "goimports"

" Setup for custom global mappings
nnoremap <SPACE> <Nop>
set nocompatible              " be iMproved, required
filetype off                  " required

set ignorecase
set smartcase
set hidden
set noerrorbells
set scrolloff=8
set signcolumn=yes

" custom setting
set clipboard=unnamed " use system clipboard
set mouse=v
set number
set encoding=utf-8
set backspace=indent,eol,start
set cursorline
set guioptions=

" indent for global
set expandtab
set shiftwidth=4
set softtabstop=4
set autoindent
set relativenumber

syntax on
syntax enable
" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim

" Custom shortcuts
nmap <F8> :TagbarToggle<CR>
nnoremap ,<space> :nohlsearch<CR>

call vundle#begin()
" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'

" all plugin
Plugin 'mhinz/vim-startify'
Plugin 'Valloric/YouCompleteMe'
Plugin 'vim-syntastic/syntastic'

Plugin 'fatih/vim-go'

Plugin 'scrooloose/nerdtree'
Plugin 'vim-airline/vim-airline'
Plugin 'Raimondi/delimitMate'

" Automatic closing of brackets matching
" Plugin 'morhetz/gruvbox'

" F8 shortcut
Plugin 'majutsushi/tagbar'

Plugin 'Yggdroot/indentLine'

Plugin 'hashivim/vim-terraform'

Plugin 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plugin 'junegunn/fzf.vim'

Plugin 'terryma/vim-multiple-cursors'

Plugin 'tpope/vim-surround'
Plugin 'mattn/emmet-vim'

Plugin 'dense-analysis/ale'
Plugin 'sheerun/vim-polyglot'
Plugin 'joshdick/onedark.vim'

Plugin 'christoomey/vim-system-copy'

" All of your Plugins must be added before the following line
call vundle#end()            " required
filetype plugin indent on    " required

colorscheme onedark

" indent for special file
autocmd FileType c,cpp setlocal expandtab shiftwidth=2 softtabstop=2 cindent
autocmd FileType python setlocal expandtab shiftwidth=4 softtabstop=4 autoindent
autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab

" setup for ycm
let g:ycm_global_ycm_extra_conf = '~/.vim/bundle/YouCompleteMe/third_party/ycmd/examples/.ycm_extra_conf.py'
let g:ycm_python_binary_path = 'python'
let g:ycm_complete_in_comments = 1
let g:ycm_autoclose_preview_window_after_completion = 1
let g:ycm_autoclose_preview_window_after_insertion = 1
let g:ycm_semantic_triggers =  {
  \ 'c' : ['re!\w{2}'],
  \ 'cpp' : ['re!\w{2}'],
  \ 'python' : ['re!\w{2}'],
  \ }

" setup for syntastic
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
let g:syntastic_always_populate_loc_list = 0
let g:syntastic_auto_loc_list = 0
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 0
let g:syntastic_python_checkers = ['flake8']

" setup for terraform
let g:terraform_fmt_on_save=1
let g:terraform_align=1

" autoformat
augroup autoformat_settings
  autocmd FileType c,cpp,proto,javascript AutoFormatBuffer clang-format
  autocmd FileType python AutoFormatBuffer yapf
augroup END

" open NERDTree automatically when vim starts up on opening a directory
let NERDTreeShowHidden=1
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists("s:std_in") | exe 'NERDTree' argv()[0] | wincmd p | ene | endif

map <silent> <F5> : NERDTreeToggle<CR>
map ; :Files<CR>

" setup for gruvbox
" set t_Co=256
" set background=dark
" colorscheme industry
" let g:gruvbox_contrast_dark = 'soft'

" setup for ctrlp
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlP'
let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_custom_ignore = '\v[\/]\.(git|hg|svn)$'
let g:ctrlp_custom_ignore = {
  \ 'dir':  '\v[\/]\.(git|hg|svn)$',
  \ 'file': '\v\.(exe|so|dll)$',
  \ 'link': 'some_bad_symbolic_links',
  \ }
set wildignore+=*/tmp/*,*.so,*.swp,*.zip


" setup for indent line
let g:indentLine_char = '│'
set tags=./tags,tags;$HOME
"source ~/cscope_maps.vim

let g:go_fmt_command = "goimports"

" Setup for custom global mappings
nnoremap <SPACE> <Nop>
map <Space> <Leader>
