"set runtimepath^=~/.vim runtimepath+=~/.vim/after
"    let &packpath = &runtimepath
"    source ~/.vimrc

set nocompatible
syntax enable
syntax on
filetype on
filetype plugin on

set nolist
set ignorecase
set smartcase
set hidden
set noerrorbells
set scrolloff=8
set signcolumn=yes
set hlsearch
" set autochdir
set updatetime=300

" set split directions
set splitbelow
set splitright
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

nnoremap <leader>dd :Lexplore %:p:h<CR>
nnoremap <Leader>da :Lexplore<CR>

" Move line of text up and down
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv
inoremap <C-j> <esc>:m .+1<CR>==
inoremap <C-k> <esc>:m .-2<CR>==
nnoremap <leader>k :m .-2<CR>==
nnoremap <leader>j :m .+1<CR>==

" Select last pasted text
nnoremap gp `[v`]

nnoremap <leader>ex :echo shellescape(expand('<cword>'))<Cr>

" Add line below without entering insert mode!
nnoremap <silent> <leader><Up>   :<c-u>put!=repeat([''],v:count)<bar>']+1<cr>
nnoremap <silent> <leader><Down> :<c-u>put =repeat([''],v:count)<bar>'[-1<cr>

map  <Leader>o <Plug>(easymotion-prefix)
map  <Leader>of <Plug>(easymotion-bd-f)

nnoremap <leader>sw dawelp

" CoC Extension
nmap <Leader>e <Cmd>CocCommand explorer<CR>

nmap <Leader>f [fzf-p]
xmap <Leader>f [fzf-p]

nnoremap <silent> [fzf-p]p     :<C-u>CocCommand fzf-preview.FromResources project_mru git<CR>
nnoremap <silent> [fzf-p]pf    :<C-u>CocCommand fzf-preview.ProjectFiles<CR>
nnoremap <silent> [fzf-p]gs    :<C-u>CocCommand fzf-preview.GitStatus<CR>
nnoremap <silent> [fzf-p]ga    :<C-u>CocCommand fzf-preview.GitActions<CR>
nnoremap <silent> [fzf-p]b     :<C-u>CocCommand fzf-preview.Buffers<CR>
nnoremap <silent> [fzf-p]B     :<C-u>CocCommand fzf-preview.AllBuffers<CR>
nnoremap <silent> [fzf-p]m     :<C-u>CocCommand fzf-preview.MruFiles<CR>
nnoremap <silent> [fzf-p]o     :<C-u>CocCommand fzf-preview.FromResources buffer project_mru<CR>
nnoremap <silent> [fzf-p]<C-o> :<C-u>CocCommand fzf-preview.Jumps<CR>
nnoremap <silent> [fzf-p]g;    :<C-u>CocCommand fzf-preview.Changes<CR>
nnoremap <silent> [fzf-p]/     :<C-u>CocCommand fzf-preview.Lines--add-fzf-arg=--no-sort --add-fzf-arg=--query="'"<CR>
nnoremap <silent> [fzf-p]*     :<C-u>CocCommand fzf-preview.Lines --add-fzf-arg=--no-sort --add-fzf-arg=--query="'<C-r>=expand('<cword>')<CR>"<CR>
nnoremap          [fzf-p]gr    :<C-u>CocCommand fzf-preview.ProjectGrep<Space>
xnoremap          [fzf-p]gr    "sy:CocCommand   fzf-preview.ProjectGrep<Space>-F<Space>"<C-r>=substitute(substitute(@s, '\n', '', 'g'), '/', '\\/', 'g')<CR>"
nnoremap <silent> [fzf-p]t     :<C-u>CocCommand fzf-preview.BufferTags<CR>
nnoremap <silent> [fzf-p]q     :<C-u>CocCommand fzf-preview.QuickFix<CR>
nnoremap <silent> [fzf-p]L     :<C-u>CocCommand fzf-preview.LocationList<CR> 

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

" Accept first grammar correction
nnoremap <Leader>c 1z=
nnoremap <Leader>gl }
" nnoremp <leader>sv :source /Users/p.zaniewski/.config/nvim/init.vim<CR>
nnoremap <leader>sv :source /home/decoder/.config/nvim/init.vim<CR>

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

" SHORTCUTS REMAPS
" Stop search highlight
nnoremap ,<space> :nohlsearch<CR>

" jj in insert mode instead of ESC
inoremap jj <Esc>
inoremap jk <Esc>

" Copies till the end of a line. Fits with Shift + D, C etc
nnoremap Y yg_

" Replace multiple words simultaniously
nnoremap <Leader>x *``cgn
nnoremap <Leader>X #``cgN

" Search and replace word under cursor using F4
nnoremap <F4> :%s/<c-r><c-w>/<c-r><c-w>/gc<c-f>$F/i

" COMMAND REMAPS
command GitDiff execute  "w !git diff --no-index -- % -"
nmap <F8> :TagbarToggle<CR>

" cut content to next header #
nmap cO :.,/^#/-1d<CR>

" copy content to next header #
nmap cY :.,/^#/-1y<CR>

tnoremap <Esc> <C-\><C-n>
command! -nargs=* T split | terminal <args>
command! -nargs=* VT vsplit | terminal <args>

"Split line in two
nnoremap <Leader>sp i<CR><Esc>

" Zoom split windows
noremap Zz <c-w>_ \| <c-w>\|
noremap Zo <c-w>=

" Find files using Telescope command-line sugar.
" map('n', '<leader>ff', "<cmd>lua require'telescope.builtin'.find_files({ find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<cr>", default_opts)
nnoremap <leader>tf <cmd>lua require'telescope.builtin'.find_files({ find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<cr>
nnoremap <leader>tg <cmd>Telescope live_grep<cr>
nnoremap <leader>tb <cmd>Telescope buffers<cr>
nnoremap <leader>th <cmd>Telescope help_tags<cr>
nnoremap <Leader>ts :lua require'telescope.builtin'.grep_string{}<CR>

" Markdown Settings
nnoremap <silent><leader>mp :MarkdownPreview<CR>

" Harpoon settings
nnoremap <Leader>ha :lua require("harpoon.mark").add_file()<CR>
nnoremap <Leader>hj :lua require("harpoon.ui").nav_file(1)<CR>
nnoremap <Leader>h1j :lua require("harpoon.ui").nav_file(2)<CR>
nnoremap <Leader>h2j :lua require("harpoon.ui").nav_file(3)<CR>
nnoremap <Leader>hm :lua require("harpoon.ui").toggle_quick_menu()<CR>

"Floatterm settings
nnoremap   <silent><Leader>fl :FloatermNew<CR>
nnoremap   <silent><Leader>ft :FloatermToggle<CR>
nnoremap   <silent><Leader>fs :FloatermShow<CR>
nnoremap   <silent><Leader>fh :FloatermHide<CR>
nnoremap   <silent><Leader>fn :FloatermNext<CR>
nnoremap   <silent><Leader>fc :FloatermKill<CR>

" Split navigation
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

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
Plugin 'nvim-lua/plenary.nvim' " don't forget to add this one if you don't have it yet!
Plugin 'ThePrimeagen/harpoon'
Plugin 'nvim-telescope/telescope.nvim'
Plugin 'nvim-telescope/telescope-fzf-native.nvim', { 'do': 'make' }
Plugin 'voldikss/vim-floaterm'
Plugin 'easymotion/vim-easymotion'

" Editing related
Plugin 'Raimondi/delimitMate'
Plugin 'godlygeek/tabular'
Plugin 'plasticboy/vim-markdown'
Plugin 'mattn/webapi-vim'
Plugin 'Yggdroot/indentLine'
Plugin 'tpope/vim-surround'
Plugin 'mattn/emmet-vim'
Plugin 'wellle/targets.vim'
Plugin 'terryma/vim-multiple-cursors'
Plugin 'vim-syntastic/syntastic'
Plugin 'sheerun/vim-polyglot'
Plugin 'iamcco/markdown-preview.nvim'
Plugin 'junegunn/vim-emoji'
Plugin 'christoomey/vim-system-copy'
Plugin 'dhruvasagar/vim-table-mode'
Plugin 'junegunn/goyo.vim'
Plugin 'junegunn/limelight.vim'
Plugin 'ferrine/md-img-paste.vim'
Plugin 'SidOfc/mkdx'
Plugin 'weirongxu/plantuml-previewer.vim'
Plugin 'tyru/open-browser.vim'
Plugin 'dhruvasagar/vim-open-url'
Plugin 'hrsh7th/vim-vsnip'
Plugin 'hrsh7th/vim-vsnip-integ'
Plugin 'sakshamgupta05/vim-todo-highlight'
Plugin 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}  " We recommend updating the parsers on update

" Programming
Plugin 'majutsushi/tagbar'
Plugin 'hashivim/vim-terraform'
Plugin 'fatih/vim-go'
Plugin 'neoclide/coc.nvim', { 'branch': 'master', 'do': 'yarn install --frozen-lockfile' }
Plugin 'dense-analysis/ale'
Plugin 'tpope/vim-fugitive'

" Color Schemes
Plugin 'morhetz/gruvbox'
Plugin 'joshdick/onedark.vim'
Plugin 'srcery-colors/srcery-vim'
Plugin 'NLKNguyen/papercolor-theme'

" All of your Plugins must be added before the following line
call vundle#end()

set completefunc=emoji#complete

" *** COLOR_SCHEMES ***
set t_Co=256
set background=dark
let g:lightline = {
      \ 'colorscheme': 'PaperColor',
      \ }
colorscheme PaperColor
" colorscheme gruvbox          
" colorscheme industry
" colorscheme srcery
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

autocmd BufWritePost *.puml silent! "!java -jar /usr/local/bin/plantuml.jar <afile> -o ./rendered"

autocmd! User GoyoEnter nested call <SID>goyo_enter()
autocmd! User GoyoLeave nested call <SID>goyo_leave()

" vsnip settings
" Expand
imap <expr> <C-j>   vsnip#expandable()  ? '<Plug>(vsnip-expand)'         : '<C-j>'
smap <expr> <C-j>   vsnip#expandable()  ? '<Plug>(vsnip-expand)'         : '<C-j>'

" Expand or jump
imap <expr> <C-l>   vsnip#available(1)  ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>'
smap <expr> <C-l>   vsnip#available(1)  ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>'

" Color name (:help cterm-colors) or ANSI code
let g:limelight_conceal_ctermfg = 'gray'
let g:limelight_conceal_ctermfg = 240

autocmd FileType markdown nmap <buffer><silent> <leader>p :call mdip#MarkdownClipboardImage()<CR>
" there are some defaults for image directory and image name, you can change them
let g:mdip_imgdir = '_media'
let g:mdip_imgname = 'image'

" indent for special file
autocmd FileType c,cpp setlocal expandtab shiftwidth=2 softtabstop=2 cindent
autocmd FileType python setlocal expandtab shiftwidth=4 softtabstop=4 autoindent
autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab
autocmd FileType markdown setlocal expandtab shiftwidth=4 softtabstop=4 autoindent
au FileType plantuml let g:plantuml_previewer#plantuml_jar_path = get(
    \  matchlist(system('cat `which plantuml` | grep plantuml.jar'), '\v.*\s[''"]?(\S+plantuml\.jar).*'),
    \  1,
    \  0
    \)

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
let g:indentLine_char = '?'
set tags=./tags,tags;$HOME
"source ~/cscope_maps.vim

let g:go_fmt_command = "goimports"
