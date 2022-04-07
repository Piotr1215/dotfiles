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
set updatetime=300

set splitbelow
set splitright

set mouse=v
set number
set encoding=utf-8
set backspace=indent,eol,start
set cursorline
set guioptions=

set expandtab
set shiftwidth=5
set softtabstop=4
set autoindent
set relativenumber
set incsearch
set laststatus=3

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim

" *** REMAPS ***
" LEADER REMAPS
" Space is leader
nnoremap <SPACE> <Nop>
map <Space> <Leader>
nnoremap <Leader>q @q

map ` <Nop>

" Netrw settings
nnoremap <leader>dd :Lexplore %:p:h<CR>
nnoremap <Leader>da :Lexplore<CR>

" Move line of text up and down
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv
inoremap <C-j> <esc>:m .+1<CR>==
inoremap <C-k> <esc>:m .-2<CR>==
nnoremap <leader>k :m .-2<CR>==
nnoremap <leader>j :m .+1<CR>==

" Save buffer
nnoremap <leader>w :w<CR>

" Select last pasted text
nnoremap gp `[v`]

" Find occunrances of selected text
vnoremap // y/\V<C-R>=escape(@",'/\')<CR><CR>

" Execute word under cursor like a shell command
nnoremap <leader>ex :!<cword><Cr>

" Add line below without entering insert mode!
nnoremap <silent> <leader><Up>   :<c-u>put!=repeat([''],v:count)<bar>']+1<cr>
nnoremap <silent> <leader><Down> :<c-u>put =repeat([''],v:count)<bar>'[-1<cr>

" Easy Motion Mappings
map  <Leader>o <Plug>(easymotion-prefix)
map  <Leader>of <Plug>(easymotion-bd-f)
map  <Leader>ol <Plug>(easymotion-bd-w)

" 1. TEXT EDITING
" Easier copy/paste

" Paste at the end of line with space
:nnoremap <leader>5 A <esc>p

" Copy to 0 register
:nnoremap <leader>1 "0y

" Paste crom clipboard
:nnoremap <leader>2 "+p

" Go to next header
nnoremap <Leader>nh :.,/^#/<CR>

" Copy selection to clipboard with Ctrl+v
vmap <C-c> "+y

" Set spellcheck on/off
nnoremap <Leader>son :setlocal spell spelllang=en_us<CR>
nnoremap <Leader>sof :set nospell<CR>

" Accept first grammar correction
nnoremap <Leader>c 1z=

" Removes whitespace
nnoremap <Leader>rspace :%s/\s\+$//e

" Removes empty lines if there are more than 2
nnoremap <Leader>rlines :%s/\n\{3,}/\r\r/e

" Swap words
nnoremap <leader>sw <:s/\v([^( ]+)(\s*,\s*)([^, ]+)/\3\2\1<CR>

" Insert space
nnoremap <Leader>i i<space><esc>

" delete word forward in insert mode
inoremap <C-e> <C-o>dw<Left>

" Operations on Code Block
onoremap <silent>am <cmd>call <sid>MarkdowCodeBlock(1)<cr>
xnoremap <silent>am <cmd>call <sid>MarkdowCodeBlock(1)<cr>

onoremap <silent>im <cmd>call <sid>MarkdowCodeBlock(0)<cr>
xnoremap <silent>im <cmd>call <sid>MarkdowCodeBlock(0)<cr>

" Copies till the end of a line. Fits with Shift + D, C etc
nnoremap Y yg_

" Replace multiple words simultaniously
nnoremap <Leader>x *``cgn
nnoremap <Leader>X #``cgN

" Search and replace word under cursor using F4
nnoremap <F4> :%s/<c-r><c-w>/<c-r><c-w>/gc<c-f>$F/i

" cut and copy content to next header #
nmap cO :.,/^#/-1d<CR>
nmap cY :.,/^#/-1y<CR>

"Split line in two
nnoremap <Leader>sp i<CR><Esc>

" Markdown Previe
nnoremap <silent><leader>mp :MarkdownPreview<CR>

" Find and replace
nnoremap <Space><Space> :%s/\<<C-r>=expand("<cword>")<CR>\>/

" Upload selected to ix.io
vnoremap <Leader>pp :w !curl -F "f:1=<-" ix.io<CR>

" Fix Markdown Errors
nnoremap <leader>fx :<C-u>CocCommand markdownlint.fixAll<CR>

" Move screen to contain current line at the top
nnoremap <leader>d zt

" Abbreviations
iab <expr> t/ strftime('TODO(' . $USER . ' %Y-%m-%d):')

" 2. NAVIGATION
" CoC Extension
nmap <Leader>f [fzf-p]
xmap <Leader>f [fzf-p]

" Files and Projects navigation
nnoremap <silent> [fzf-p]p     :<C-u>CocCommand fzf-preview.FromResources project_mru git<CR>
nnoremap <silent> [fzf-p]pf    :<C-u>CocCommand fzf-preview.ProjectFiles<CR>
nnoremap <silent> [fzf-p]gs    :<C-u>CocCommand fzf-preview.GitStatus<CR>
nnoremap <silent> [fzf-p]ga    :<C-u>CocCommand fzf-preview.GitActions<CR>
nnoremap <silent> [fzf-p]b     :<C-u>CocCommand fzf-preview.Buffers<CR>
nnoremap <silent> [fzf-p]B     :<C-u>CocCommand fzf-preview.AllBuffers<CR>
nnoremap <silent> [fzf-p]m     :<C-u>CocCommand fzf-preview.MruFiles<CR>
nnoremap <silent> [fzf-p]po     :<C-u>CocCommand fzf-preview.FromResources buffer project_mru<CR>
nnoremap <silent> [fzf-p]<C-o> :<C-u>CocCommand fzf-preview.Jumps<CR>
nnoremap <silent> [fzf-p]g;    :<C-u>CocCommand fzf-preview.Changes<CR>
nnoremap <silent> [fzf-p]/     :<C-u>CocCommand fzf-preview.Lines--add-fzf-arg=--no-sort --add-fzf-arg=--query="'"<CR>
nnoremap <silent> [fzf-p]*     :<C-u>CocCommand fzf-preview.Lines --add-fzf-arg=--no-sort --add-fzf-arg=--query="'<C-r>=expand('<cword>')<CR>"<CR>
nnoremap          [fzf-p]gr    :<C-u>CocCommand fzf-preview.ProjectGrep<Space>
xnoremap          [fzf-p]gr    "sy:CocCommand   fzf-preview.ProjectGrep<Space>-F<Space>"<C-r>=substitute(substitute(@s, '\n', '', 'g'), '/', '\\/', 'g')<CR>"
nnoremap <silent> [fzf-p]t     :<C-u>CocCommand fzf-preview.BufferTags<CR>
nnoremap <silent> [fzf-p]q     :<C-u>CocCommand fzf-preview.QuickFix<CR>
nnoremap <silent> [fzf-p]L     :<C-u>CocCommand fzf-preview.LocationList<CR>

" Find files using Telescope command-line sugar.
" map('n', '<leader>ff', "<cmd>lua require'telescope.builtin'.find_files({ find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<cr>", default_opts)
let g:rooter_patterns = ['.git', 'package.json', '!node_modules']
nnoremap <leader>tf <cmd>lua require'telescope.builtin'.find_files({ find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<cr>
nnoremap <leader>tg <cmd>Telescope live_grep<cr>
nnoremap <leader>to <cmd>Telescope oldfiles<cr>
nnoremap <leader>tb <cmd>Telescope buffers<cr>
nnoremap <leader>th <cmd>Telescope help_tags<cr>
nnoremap <Leader>ts :lua require'telescope.builtin'.grep_string{}<CR>
nnoremap <leader>tp <cmd>Telescope find_files<cr>
nnoremap <leader>tl <cmd>Telescope repo list<cr>

" Git mappings
nnoremap <leader>goh :G push -f origin HEAD<CR>
nnoremap <leader>gop :G push<CR>
command GitDiff execute  "w !git diff --no-index -- % -"

" Used for learning for certs
nnoremap <Leader>ok A :+1: <esc><CR>
nnoremap <Leader>bad A :-1: <esc><CR>
nnoremap <Leader>r A :hand: <esc><CR>
nnoremap <Leader>clean :g/<details>/,/<\/details>/d _<CR>

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

function! Reformat()
  execute '%s/\v(\[!TIP\].*)/\1\r:::/g'
  execute '%s/> \[!TIP\]/:::tip\r/g'
  execute '%s/\v(\[!INFO\].*)/\1\r:::/g'
  execute '%s/> \[!INFO\]/:::info\r/g'
  execute '%s/\v(\[!NOTE\].*)/\1\r:::/g'
  execute '%s/> \[!NOTE\]/:::note\r/g'
  execute '%s/\v(\[!WARNING\].*)/\1\r:::/g'
  execute '%s/> \[!WARNING\]/:::danger\r/g'
  execute '%s/\v(\[!ATTENTION\].*)/\1\r:::/g'
  execute '%s/> \[!ATTENTION\]/:::caution\r/g'
endfunction

nnoremap <leader>mm :call Reformat()<cr>

" 3 - VIM HELPERS
" Stop search highlight
nnoremap ,<space> :nohlsearch<CR>

" Copy function or routine body and keyword
nnoremap <silent> yaf [m{jV]m%y

" jj in insert mode instead of ESC
inoremap jj <Esc>
inoremap jk <Esc>

" Zoom split windows
noremap Zz <c-w>_ \| <c-w>\|
noremap Zo <c-w>=

nmap <F8> :TagbarToggle<CR>

tnoremap <Esc> <C-\><C-n>
autocmd TermOpen term://* startinsert
command! -nargs=* T :split | resize 15 | terminal
"command! -nargs=* T split | terminal <args>
command! -nargs=* VT vsplit | terminal <args>

" Split navigation
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

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
Plugin 'rafamadriz/friendly-snippets'
Plugin 'airblade/vim-rooter'
Plugin 'cljoly/telescope-repo.nvim'

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
Plugin 'neoclide/coc.nvim', {'branch': 'release'}
Plugin 'rhysd/vim-clang-format'
Plugin 'dense-analysis/ale'
Plugin 'tpope/vim-fugitive'

" Color Schemes
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

filetype plugin indent on

" Use tab for trigger completion with characters ahead and navigate.
" NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
" other plugin before putting this into your config.
inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Use <c-space> to trigger completion.
if has('nvim')
  inoremap <silent><expr> <c-space> coc#refresh()
else
  inoremap <silent><expr> <c-@> coc#refresh()
endif

" Make <CR> auto-select the first completion item and notify coc.nvim to
" format on enter, <cr> could be remapped by other vim plugin
inoremap <silent><expr> <cr> pumvisible() ? coc#_select_confirm()
                              \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

" Use `[g` and `]g` to navigate diagnostics
" Use `:CocDiagnostics` to get all diagnostics of current buffer in location list.
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)

" GoTo code navigation.
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gimp <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Use K to show documentation in preview window.
nnoremap <silent> K :call <SID>show_documentation()<CR>

function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  elseif (coc#rpc#ready())
    call CocActionAsync('doHover')
  else
    execute '!' . &keywordprg . " " . expand('<cword>')
  endif
endfunction

" Highlight the symbol and its references when holding the cursor.
autocmd CursorHold * silent call CocActionAsync('highlight')

" Symbol renaming.
nmap <leader>rn <Plug>(coc-rename)

" Formatting selected code.
xmap <leader>fo  <Plug>(coc-format-selected)
nmap <leader>fo  <Plug>(coc-format-selected)

augroup mygroup
  autocmd!
  " Setup formatexpr specified filetype(s).
  autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
  " Update signature help on jump placeholder.
  autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
augroup end

" Applying codeAction to the selected region.
" Example: `<leader>aap` for current paragraph
xmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>a  <Plug>(coc-codeaction-selected)

" Remap keys for applying codeAction to the current buffer.
nmap <leader>ac  <Plug>(coc-codeaction)
" Apply AutoFix to problem on the current line.
nmap <leader>qf  <Plug>(coc-fix-current)

" Map function and class text objects
" NOTE: Requires 'textDocument.documentSymbol' support from the language server.
xmap if <Plug>(coc-funcobj-i)
omap if <Plug>(coc-funcobj-i)
xmap af <Plug>(coc-funcobj-a)
omap af <Plug>(coc-funcobj-a)
xmap ic <Plug>(coc-classobj-i)
omap ic <Plug>(coc-classobj-i)
xmap ac <Plug>(coc-classobj-a)
omap ac <Plug>(coc-classobj-a)

" Use CTRL-S for selections ranges.
" Requires 'textDocument/selectionRange' support of language server.
nmap <silent> <C-s> <Plug>(coc-range-select)
xmap <silent> <C-s> <Plug>(coc-range-select)

" Add `:Format` command to format current buffer.
command! -nargs=0 Format :call CocAction('format')

" Add `:Fold` comand to fold current buffer.
command! -nargs=? Fold :call     CocAction('fold', <f-args>)

" Add `:OR` command for organize imports of the current buffer.
command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organizeImport')

" Use <Ctrl-F> to format documents with prettier
command! -nargs=0 Prettier :CocCommand prettier.formatFile
noremap <C-F> :Prettier<CR>

" Add (Neo)Vim's native statusline support.
" NOTE: Please see `:h coc-status` for integrations with external plugins that
" provide custom statusline: lightline.vim, vim-airline.
set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}

"autocmd BufWritePost *.puml silent! !java -DPLANTUML_LIMIT_SIZE=8192 -jar /usr/local/bin/plantuml.jar <afile> -o ./rendered
autocmd BufWritePost *.puml silent! !java -DPLANTUML_LIMIT_SIZE=8192 -jar /usr/local/bin/plantuml.jar -tsvg <afile> -o ./rendered

" vsnip settings
" Expand
imap <expr> <C-j>   vsnip#expandable()  ? '<Plug>(vsnip-expand)'         : '<C-j>'
smap <expr> <C-j>   vsnip#expandable()  ? '<Plug>(vsnip-expand)'         : '<C-j>'

" Expand or jump
imap <expr> <C-l>   vsnip#available(1)  ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>'
smap <expr> <C-l>   vsnip#available(1)  ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>'

" Select or cut text to use as $TM_SELECTED_TEXT in the next snippet.
" See https://github.com/hrsh7th/vim-vsnip/pull/50
nmap <leader>t   <Plug>(vsnip-select-text)
xmap <leader>t   <Plug>(vsnip-select-text)
nmap <leader>tc   <Plug>(vsnip-cut-text)
xmap <leader>tc   <Plug>(vsnip-cut-text)

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

"au FileType plantuml let g:plantuml_previewer#plantuml_jar_path = get(
"    \  matchlist(system('cat `which plantuml` | grep plantuml.jar'), '\v.*\s[''"]?(\S+plantuml\.jar).*'),
"    \  1,
"    \  0
"    \)

let g:plantuml_previewer#viewer_path = "/home/decoder/.vim/bundle/plantuml-previewer.vim/viewer"

" setup custom emmet snippets
let g:user_emmet_settings = webapi#json#decode(join(readfile(expand('~/.snippets_custom.json')), "\n"))

" setup for netrw
let g:netrw_winsize = 30
let g:netrw_banner = 0
let g:netrw_keepdir = 0

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
let g:vim_markdown_new_list_item_indent = 0

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
  autocmd FileType c,cpp,proto,javascript setlocal equalprg=clang-format
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
let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_structs = 1
let g:go_highlight_interfaces = 1
let g:go_highlight_operators = 1
