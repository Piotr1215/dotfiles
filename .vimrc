set nocompatible
syntax enable
filetype on
filetype plugin on

set ignorecase
set smartcase
set hidden
set noerrorbells
set scrolloff=8
set signcolumn=yes
set hlsearch

" custom setting
set mouse=v
set number
set encoding=utf-8
set backspace=indent,eol,start
set cursorline
set guioptions=

" indent for global
set expandtab
set shiftwidth=5
set softtabstop=4
set autoindent
set relativenumber
set incsearch

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim

" *** REMAPS ***
" LEADER REMAPS
" Space is leader
nnoremap <SPACE> <Nop>
map <Space> <Leader>

" Move line of text up and down
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv
inoremap <C-j> <esc>:m .+1<CR>==
inoremap <C-k> <esc>:m .-2<CR>==
nnoremap <leader>k :m .-2<CR>==
nnoremap <leader>j :m .+1<CR>==

" Add line below without entering insert mode!
nnoremap <silent> <leader><Up>   :<c-u>put!=repeat([''],v:count)<bar>']+1<cr>
nnoremap <silent> <leader><Down> :<c-u>put =repeat([''],v:count)<bar>'[-1<cr>

" Enclose highlighted parts in brackets etc
vnoremap <leader>' <esc>`>a'<esc>`<i'<esc>
vnoremap <leader>" <esc>`>a"<esc>`<i"<esc>
vnoremap <leader>( <esc>`>a)<esc>`<i(<esc>
vnoremap <leader>[ <esc>`>a]<esc>`<i[<esc>
vnoremap <leader>{ <esc>`>a}<esc>`<i{<esc>

" Edit current file in different ways
cnoremap %% <C-R>=fnameescape(expand('%:h')).'/'<cr>
map <leader>ew :e %%
map <leader>es :sp %%
map <leader>ev :vsp %%
map <leader>et :tabe %%

" Copy line from above and inser under cursor and enter inser mode from the
nnoremap <Leader>c 1ky$jp0i

" go to next header
nnoremap  <Leader>nh :.,/^#/-1<CR>

" Show buffers
nnoremap <Leader>b :Buffers<CR>

" delete white space
nnoremap <Leader>rspace :%s/\s\+$//e

" delete lines if there is more than one empty line
nnoremap <Leader>rlines :%s/\n\{3,}/\r\r/e

" When learning for exam, used as scoring mechanism
nnoremap <Leader>ok A :+1: <esc><CR>
nnoremap <Leader>bad A :-1: <esc><CR>
nnoremap <Leader>r A :hand: <esc><CR>

" SHORTCUTS REMAPS
" Stop search highlight
nnoremap ,<space> :nohlsearch<CR>
map ; :Files<CR>

" delete word forward in insert mode
inoremap <C-e> <C-o>dw<Left>

" cut content to next header
nmap cO :.,/^#/-1d<CR>

" jj in insert mode instead of ESC
inoremap jj <Esc> 
inoremap jk <Esc> 

" Copies till the end of a line. Fits with Shift + D, C etc
nnoremap Y y_

" Replace multiple words simultaniously
nnoremap cn *``cgn
nnoremap cN *``cgN

" COMMAND REMAPS
nmap <F8> :TagbarToggle<CR>

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

Plugin 'vim-airline/vim-airline'
Plugin 'Raimondi/delimitMate'

Plugin 'morhetz/gruvbox'

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
" Plugin 'joshdick/onedark.vim'

Plugin 'christoomey/vim-system-copy'

Plugin 'godlygeek/tabular'
Plugin 'plasticboy/vim-markdown'
Plugin 'mattn/webapi-vim'

Plugin 'iamcco/markdown-preview.nvim' 

Plugin 'sakshamgupta05/vim-todo-highlight'

Plugin 'tpope/vim-fugitive'

Plugin 'junegunn/vim-emoji'

" Track the engine.
Plugin 'SirVer/ultisnips'

" Snippets are separated from the engine. Add this if you want them:
Plugin 'honza/vim-snippets'

Plugin 'ctrlpvim/ctrlp.vim'

" All of your Plugins must be added before the following line
call vundle#end()            
filetype plugin indent on   
set completefunc=emoji#complete

" Trigger configuration. You need to change this to something other than <tab> if you use one of the following:
" - https://github.com/Valloric/YouCompleteMe
" - https://github.com/nvim-lua/completion-nvim
let g:UltiSnipsExpandTrigger="<c-q>"
let g:UltiSnipsJumpForwardTrigger="<c-b>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"

" If you want :UltiSnipsEdit to split your window.
let g:UltiSnipsEditSplit="vertical"

" indent for special file
autocmd FileType c,cpp setlocal expandtab shiftwidth=2 softtabstop=2 cindent
autocmd FileType python setlocal expandtab shiftwidth=4 softtabstop=4 autoindent
autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab

" setup custom emmet snippets
let g:user_emmet_settings = webapi#json#decode(join(readfile(expand('~/.snippets_custom.json')), "\n"))

" setup for markdown snippet
let g:vim_markdown_folding_disabled = 1 
let g:vim_markdown_folding_level = 3
let g:vim_markdown_toc_autofit = 1
let g:vim_markdown_conceal = 0
let g:vim_markdown_conceal_code_blocks = 0
let g:vim_markdown_no_extensions_in_markdown = 1
let g:vim_markdown_autowrite = 1

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

augroup vimrc_todo
    au!
    au Syntax * syn match MyTodo /\v<(FIXME|NOTE|TODO|OPTIMIZE|XXX):/
          \ containedin=.*Comment,vimCommentTitle
augroup END
hi def link MyTodo Todo

autocmd StdinReadPre * let s:std_in=1
" autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists("s:std_in") | exe 'NERDTree' argv()[0] | wincmd p | ene | endif

" setup for gruvbox
set t_Co=256
set background=dark
colorscheme gruvbox
" colorscheme industry
let g:gruvbox_contrast_dark = 'soft'

" setup for ctrlp
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlPMixed'
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
