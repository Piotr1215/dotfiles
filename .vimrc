set nocompatible
syntax enable
syntax on
filetype on
filetype plugin on

set ignorecase
set smartcase
set hidden
set noerrorbells
set scrolloff=8
set signcolumn=yes
set hlsearch
set autochdir

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

nnoremap <Leader>q @q

map ` <Nop>
nnoremap <leader>nf :NERDTreeFocus<CR>
nnoremap <leader>ne :NERDTree<CR>
nnoremap <leader>nt :NERDTreeToggle<CR>
nnoremap <leader>nfi :NERDTreeFind<CR>

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

" Edit current file in different ways
cnoremap %% <C-R>=fnameescape(expand('%:h')).'/'<cr>
map <leader>ew :e %%
map <leader>es :sp %%
map <leader>ev :vsp %%
map <leader>et :tabe %%

" Removes whitespace
" Removes empty lines if there are more than 2
nnoremap <Leader>rspace :%s/\s\+$//e
nnoremap <Leader>rlines :%s/\n\{3,}/\r\r/e

map asd <Plug>Markdown_MoveToParentHeader
nnoremap <Leader>ph <Plug>Markdown_MoveToPreviousHeader
nnoremap <Leader>nh :.,/^#/<CR>

" Set spellcheck on/off
nnoremap <Leader>son :setlocal spell spelllang=en_us<CR>
nnoremap <Leader>sof :set nospell<CR>

" Used for learning for certs
nnoremap <Leader>ok A :+1: <esc><CR>
nnoremap <Leader>bad A :-1: <esc><CR>
nnoremap <Leader>r A :hand: <esc><CR>
nnoremap <Leader>clean :g/<details>/,/<\/details>/d _<CR>

" delete word forward in insert mode
inoremap <C-e> <C-o>dw<Left>

nnoremap <Leader>i i<space><esc>

" Copy line from above and inser under cursor and enter inser mode from the
nnoremap <Leader>c 1ky$jp0i
nnoremap <Leader>gl }
nnoremap <leader>sv :source ~/.vimrc<CR>

"Floaterm
nnoremap <silent><Leader>ft :FloatermNew<CR>

function! s:MarkdowCodeBlock(outside)
    call search('```', 'cb')
    if a:outside
        normal! Vo
    else
        normal! j0Vo
    endif
    call search('```')
    if ! a:outside
        normal! k
    endif
endfunction

onoremap <silent>am <cmd>call <sid>MarkdowCodeBlock(1)<cr>
xnoremap <silent>am <cmd>call <sid>MarkdowCodeBlock(1)<cr>

onoremap <silent>im <cmd>call <sid>MarkdowCodeBlock(0)<cr>
xnoremap <silent>im <cmd>call <sid>MarkdowCodeBlock(0)<cr>

" Goyo and limelight
nmap <Leader>l <Plug>(Limelight)
xmap <Leader>l <Plug>(Limelight)

autocmd! User GoyoEnter Limelight
autocmd! User GoyoLeave Limelight!

" SHORTCUTS REMAPS
" Stop search highlight
nnoremap ,<space> :nohlsearch<CR>

" jj in insert mode instead of ESC
inoremap jj <Esc>
inoremap jk <Esc>

" Copies till the end of a line. Fits with Shift + D, C etc
nnoremap Y y_

" Replace multiple words simultaniously
nnoremap cn *``cgn
nnoremap cN *``cgN

" COMMAND REMAPS
command GitDiff execute  "w !git diff --no-index -- % -"
nmap <F8> :TagbarToggle<CR>

" Replace multiple words simultaniously
nnoremap <Leader>x *``cgn
nnoremap <Leader>X #``cgN

" Split line in two
nnoremap <Leader>sp i<CR><Esc>

" Zoom split windows
noremap Zz <c-w>_ \| <c-w>\|
noremap Zo <c-w>=

"cut content to next header #
nmap cO :.,/^#/-1d<CR>

if has('nvim')
    " Find files using Telescope command-line sugar.
    nnoremap <leader>ff <cmd>Telescope find_files<cr>
    nnoremap <leader>fg <cmd>Telescope live_grep<cr>
    nnoremap <leader>fb <cmd>Telescope buffers<cr>
    nnoremap <leader>fh <cmd>Telescope help_tags<cr>

    " Harpoon settings
    nnoremap <Leader>ha :lua require("harpoon.mark").add_file()<CR>
    nnoremap <Leader>hj :lua require("harpoon.ui").nav_file(1)<CR>
    nnoremap <Leader>h1j :lua require("harpoon.ui").nav_file(2)<CR>
    nnoremap <Leader>h2j :lua require("harpoon.ui").nav_file(3)<CR>
    nnoremap <Leader>hm :lua require("harpoon.ui").toggle_quick_menu()<CR>
    nnoremap <Leader>gs :lua require'telescope.builtin'.grep_string{}<CR>
endif

"Floatterm settings
nnoremap   <silent><Leader>fl :FloatermNew<CR>
nnoremap   <silent><Leader>ft :FloatermToggle<CR>
nnoremap   <silent><Leader>fs :FloatermShow<CR>
nnoremap   <silent><Leader>fh :FloatermHide<CR>

" Goyo shortcuts
nnoremap   <silent><Leader>go :Goyo 100<CR>

call vundle#begin()
" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'

" Editor functionality
Plugin 'mhinz/vim-startify'
Plugin 'vim-airline/vim-airline'
Plugin 'ryanoasis/vim-devicons'
Plugin 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plugin 'junegunn/fzf.vim'
Plugin 'ctrlpvim/ctrlp.vim'
Plugin 'voldikss/vim-floaterm'    
Plugin 'hrsh7th/vim-vsnip'
Plugin 'hrsh7th/vim-vsnip-integ'

if has('nvim')
    Plugin 'nvim-lua/plenary.nvim' " don't forget to add this one if you don't have it yet!
    Plugin 'ThePrimeagen/harpoon'
    Plugin 'nvim-telescope/telescope.nvim'
    Plugin 'nvim-telescope/telescope-fzf-native.nvim', { 'do': 'make' }
endif

" Editing related
Plugin 'Raimondi/delimitMate'
Plugin 'godlygeek/tabular'
Plugin 'plasticboy/vim-markdown'
Plugin 'mattn/webapi-vim'
Plugin 'Yggdroot/indentLine'
Plugin 'tpope/vim-surround'
Plugin 'mattn/emmet-vim'
Plugin 'preservim/nerdtree'
Plugin 'wellle/targets.vim'
Plugin 'terryma/vim-multiple-cursors'
Plugin 'vim-syntastic/syntastic'
Plugin 'sheerun/vim-polyglot'
Plugin 'iamcco/markdown-preview.nvim'
Plugin 'junegunn/vim-emoji'
Plugin 'christoomey/vim-system-copy'
Plugin 'dhruvasagar/vim-table-mode'
Plugin 'junegunn/limelight.vim'
Plugin 'junegunn/goyo.vim'
Plugin 'ferrine/md-img-paste.vim'
"Plugin 'SidOfc/mkdx'
Plugin 'weirongxu/plantuml-previewer.vim'
Plugin 'tyru/open-browser.vim'

" Programming
Plugin 'majutsushi/tagbar'
Plugin 'hashivim/vim-terraform'
Plugin 'fatih/vim-go'
Plugin 'neoclide/coc.nvim', {'branch': 'release'}
Plugin 'dense-analysis/ale'
Plugin 'tpope/vim-fugitive'
Plugin 'SirVer/ultisnips'
Plugin 'honza/vim-snippets'

" Color Schemes
Plugin 'morhetz/gruvbox'
Plugin 'joshdick/onedark.vim'
Plugin 'srcery-colors/srcery-vim'
Plugin 'NLKNguyen/papercolor-theme'

" All of your Plugins must be added before the following line
call vundle#end()

" Expand
imap <expr> <C-j>   vsnip#expandable()  ? '<Plug>(vsnip-expand)'         : '<C-j>'
smap <expr> <C-j>   vsnip#expandable()  ? '<Plug>(vsnip-expand)'         : '<C-j>'

" Expand or jump
imap <expr> <C-l>   vsnip#available(1)  ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>'
smap <expr> <C-l>   vsnip#available(1)  ? '<Plug>(vsnip-expand-or-jump)' : '<C-l

" *** COLOR_SCHEMES ***
set t_Co=256
set background=dark
let g:lightline = {
      \ 'colorscheme': 'PaperColor',
      \ }
" let g:onedark_termcolors=16
" let g:dracula_termcolors=16
" colorscheme gruvbox          
" colorscheme industry
" colorscheme srcery
colorscheme PaperColor
let g:gruvbox_contrast_dark = 'hard'

filetype plugin indent on

" Completion trigger
inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

" Use <c-space> to trigger completion.
inoremap <silent><expr> <c-space> coc#refresh()

" Use <cr> to confirm completion, `<C-g>u` means break undo chain at current
" position. Coc only does snippet and additional edit on confirm.
" <cr> could be remapped by other vim plugin, try `:verbose imap <CR>`.
if exists('*complete_info')
  inoremap <expr> <cr> complete_info()["selected"] != "-1" ? "\<C-y>" : "\<C-g>u\<CR>"
else
  inoremap <expr> <cr> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"
endif

"Goyo settings
" Color name (:help cterm-colors) or ANSI code
let g:limelight_conceal_ctermfg = 'gray'
let g:limelight_conceal_ctermfg = 240

"Markdown settings
"let g:mkdx#settings     = { 'highlight': { 'enable': 1 },
"                        \ 'enter': { 'shift': 1 },
"                        \ 'links': { 'external': { 'enable': 1 } },
"                        \ 'toc': { 'text': 'Table of Contents', 'update_on_write': 1 },
"                        \ 'fold': { 'enable': 1 } }
"let g:polyglot_disabled = ['markdown']
"Goyo config
function! s:goyo_enter()
  if executable('tmux') && strlen($TMUX)
    silent !tmux set status off
    silent !tmux list-panes -F '\#F' | grep -q Z || tmux resize-pane -Z
  endif
  set noshowmode
  set noshowcmd
  set scrolloff=999
  Limelight
  " ...
endfunction

function! s:goyo_leave()
  if executable('tmux') && strlen($TMUX)
    silent !tmux set status on
    silent !tmux list-panes -F '\#F' | grep -q Z && tmux resize-pane -Z
  endif
  set showmode
  set showcmd
  set scrolloff=5
  Limelight!
  " ...
endfunction

autocmd! User GoyoEnter nested call <SID>goyo_enter()
autocmd! User GoyoLeave nested call <SID>goyo_leave()

" Image paste 
autocmd FileType markdown nmap <buffer><silent> <leader>p :call mdip#MarkdownClipboardImage()<CR>
" there are some defaults for image directory and image name, you can change them
let g:mdip_imgdir = 'media'
let g:mdip_imgname = 'image'

" indent for special file
autocmd FileType c,cpp setlocal expandtab shiftwidth=2 softtabstop=2 cindent
autocmd FileType python setlocal expandtab shiftwidth=4 softtabstop=4 autoindent
autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab

" setup custom emmet snippets
let g:user_emmet_settings = webapi#json#decode(join(readfile(expand('~/.snippets_custom.json')), "\n"))

" setup for markdown snippet
let g:vim_markdown_folding_disabled = 0
let g:vim_markdown_folding_level = 3
let g:vim_markdown_toc_autofit = 1
let g:vim_markdown_conceal = 0
let g:vim_markdown_conceal_code_blocks = 0
let g:vim_markdown_no_extensions_in_markdown = 1
let g:vim_markdown_autowrite = 1
let g:vim_markdown_follow_anchor = 1
let g:vim_markdown_auto_insert_bullets = 0

" Trigger configuration. You need to change this to something other than <tab> if you use one of the following:
" - https://github.com/Valloric/YouCompleteMe
" - https://github.com/nvim-lua/completion-nvim
let g:UltiSnipsExpandTrigger="<c-q>"
let g:UltiSnipsJumpForwardTrigger="<c-b>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"

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
" autocmd StdinReadPre * let s:std_in=1
" autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists("s:std_in") | exe 'NERDTree' argv()[0] | wincmd p | ene | endif

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
