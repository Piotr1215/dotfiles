"lua require('basic')
syntax enable
syntax on
filetype on
filetype plugin indent on

set nolist
set ignorecase
set smartcase
set hidden
set noerrorbells
set scrolloff=8
set signcolumn=yes
set hlsearch
set updatetime=300
"set textwidth=80
set autochdir

set splitbelow
set splitright
set pastetoggle=<F1>

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
" Declare global variable to mark system
let uname = system('uname -s')
nnoremap <SPACE> <Nop>
map <Space> <Leader>
map ` <Nop>

if uname =~ 'Linux'
  nnoremap ö /
  inoremap ö /
endif

" MACROS
" ------ 
"
" Run q macro
nnoremap <Leader>q @q
" Execute a macro over visual line selections
xnoremap Q :'<,'>:normal @q<CR>

" MOVE AROUND
" -----------
"
" Move line of text up and down
vnoremap <S-PageDown> :m '>+1<CR>gv=gv
vnoremap <S-PageUp> :m '<-2<CR>gv=gv
inoremap <C-j> <esc>:m .+1<CR>==
inoremap <C-k> <esc>:m .-2<CR>==
nnoremap <leader>k :m .-2<CR>==
nnoremap <leader>j :m .+1<CR>==
" Go to next header
nnoremap <Leader>nh :.,/^#/<CR>

" SEARCH & REPLACE
" --------------
"
" Find occunrances of selected text
vnoremap // y/\V<C-R>=escape(@",'/\')<CR><CR>
" Easy Motion Mappings
map  <Leader>o <Plug>(easymotion-prefix)
map  <Leader>of <Plug>(easymotion-bd-f)
map  <Leader>ol <Plug>(easymotion-bd-w)
nmap  <Leader>oc <Plug>(easymotion-overwin-f2)
" Stop search highlight
nnoremap ,<space> :nohlsearch<CR>
vnoremap <C-r> "hy:%s/<C-r>h//gc<left><left><left>

" MANIPULATE TEXT
" ---------------------------
"
" Insert 2 empty lines and go into inser mode
nnoremap <leader>L O<ESC>O
nnoremap <leader>l o<cr>
" Select last pasted text
nnoremap gp `[v`]
" Add line below without entering insert mode!
nnoremap <silent> <leader><Up>   :<c-u>put!=repeat([''],v:count)<bar>']+1<cr>
nnoremap <silent> <leader><Down> :<c-u>put =repeat([''],v:count)<bar>'[-1<cr>
" Paste at the end of line with space
nnoremap <leader>5 A <esc>p
" Copy to 0 register
nnoremap <leader>1 "0y
" Paste crom clipboard
nnoremap <leader>2 "+p
" Copy selection to clipboard with Ctrl+c
vmap <C-c> "+y
" Removes whitespace
nnoremap <Leader>rspace :%s/\s\+$//e
" Removes empty lines if there are more than 2
nnoremap <Leader>rlines :%s/\n\{3,}/\r\r/e
" Insert space
nnoremap <Leader>i i<space><esc>
" delete word forward in insert mode
inoremap <C-e> <C-o>dw<Left>
" Copies till the end of a line. Fits with Shift + D, C etc
nnoremap Y yg_
" Replace multiple words simultaniously
" Repeat, with .
nnoremap <Leader>x *``cgn
nnoremap <Leader>X #``cgN
" Copy from cursor to end of line
nnoremap <leader>y "+y$
" cut and copy content to next header #
nmap cO :.,/^#/-1d<CR>
nmap cY :.,/^#/-1y<CR>
"Split line in two
nnoremap <Leader>sp i<CR><Esc>
" Swap words separated by comma
nnoremap <leader>sw :s/\v([^(]+)(\s*,\s*)([^, ]\v([^)])+)/\3\2\1<CR>
" Copy function or routine body and keyword
nnoremap <silent> yaf [m{jV]m%y

" EXTERNAL
" --------
"
" Execute line under cursor in shell
nnoremap <leader>ex :exec '!'.getline('.')<CR>
" Set spellcheck on/off
nnoremap <Leader>son :setlocal spell spelllang=en_us<CR>
nnoremap <Leader>sof :set nospell<CR>
" Accept first grammar correction
nnoremap <Leader>c 1z=
" Upload selected to ix.io
vnoremap <Leader>pp :w !curl -F "f:1=<-" ix.io<CR>
" Execute Command in scratchpad buffer
:command! -nargs=* -complete=shellcmd R new | setlocal buftype=nofile bufhidden=hide noswapfile | r !<args>
nmap <leader>sr <Plug>SendRight<cr>
xmap <silent>srv <Plug>SendRightV<cr>
nmap <leader>sd <Plug>SendDown<cr>
xmap <silent>sdv <Plug>SendDownV<cr>
" setup mapping to call :LazyGit
nnoremap <silent> <leader>gg :LazyGit<CR>

" MARKDOWN
" --------
"
" Operations on Code Block
onoremap <silent>am <cmd>call <sid>MarkdowCodeBlock(1)<cr>
xnoremap <silent>am <cmd>call <sid>MarkdowCodeBlock(1)<cr>
onoremap <silent>im <cmd>call <sid>MarkdowCodeBlock(0)<cr>
xnoremap <silent>im <cmd>call <sid>MarkdowCodeBlock(0)<cr>
" Markdown Previev
nnoremap <silent><leader>mp :MarkdownPreview<CR>
" Fix Markdown Errors
nnoremap <leader>fx :<C-u>CocCommand markdownlint.fixAll<CR>
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
" Markdown paste image
autocmd FileType markdown nmap <buffer><silent> <leader>p :call mdip#MarkdownClipboardImage()<CR>
"autocmd BufWritePost *.puml silent! !java -DPLANTUML_LIMIT_SIZE=8192 -jar /usr/local/bin/plantuml.jar <afile> -o ./rendered
autocmd BufWritePost *.puml silent! !java -DPLANTUML_LIMIT_SIZE=8192 -jar /usr/local/bin/plantuml.jar -tsvg <afile> -o ./rendered
" Auto-wrap markdown at 80 characters
" au BufRead,BufNewFile *.md setlocal textwidth=80
" Update text to 80 characters, do not update automatically
if uname =~ 'Darwin'
au FileType plantuml let g:plantuml_previewer#plantuml_jar_path = get(
    \  matchlist(system('cat `which plantuml` | grep plantuml.jar'), '\v.*\s[''"]?(\S+plantuml\.jar).*'),
    \  1,
    \  0
    \)
endif
nnoremap <leader>wi :setlocal textwidth=80<cr>

" ABBREVIATIONS
" -------------
"
iab <expr> t/ strftime('TODO(' . $USER . ' %Y-%m-%d):')

" NAVIGATION & EDITOR
" ----------
" FZF Key
nmap <Leader>f [fzf-p]
xmap <Leader>f [fzf-p]
" Files and Projects navigation
nnoremap <silent> [fzf-p]p     :<C-u>CocCommand fzf-preview.FromResources project_mru git<CR>
nnoremap <silent> [fzf-p]pf    :<C-u>CocCommand fzf-preview.ProjectFiles<CR>
nnoremap <silent> [fzf-p]gs    :<C-u>CocCommand fzf-preview.GitStatus<CR>
nnoremap <silent> [fzf-p]ga    :<C-u>CocCommand fzf-preview.GitActions<CR>
nnoremap <silent> [fzf-p]b     :<C-u>CocCommand fzf-preview.Buffers<CR>
nnoremap <silent> [fzf-p]B     :<C-u>CocCommand fzf-preview.AllBuffers<CR>
nnoremap <silent> [fzf-p]po     :<C-u>CocCommand fzf-preview.FromResources buffer project_mru<CR>
nnoremap <silent> [fzf-p]<C-o> :<C-u>CocCommand fzf-preview.Jumps<CR>
nnoremap <silent> [fzf-p]g;    :<C-u>CocCommand fzf-preview.Changes<CR>
nnoremap <silent> [fzf-p]q     :<C-u>CocCommand fzf-preview.QuickFix<CR>
nnoremap <silent> [fzf-p]L     :<C-u>CocCommand fzf-preview.LocationList<CR>
" Find files using Telescope command-line sugar.
" map('n', '<leader>ff', "<cmd>lua require'telescope.builtin'.find_files({ find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<cr>", default_opts)
nnoremap <leader>tf <cmd>lua require'telescope.builtin'.find_files({ find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<cr>
nnoremap <leader>tg <cmd>Telescope live_grep<cr>
nnoremap <leader>to <cmd>Telescope oldfiles<cr>
nnoremap <leader>tb <cmd>Telescope buffers<cr>
nnoremap <leader>th <cmd>Telescope help_tags<cr>
nnoremap <Leader>ts :lua require'telescope.builtin'.grep_string{}<CR>
nnoremap <leader>tp <cmd>Telescope find_files<cr>
nnoremap <leader>tl <cmd>Telescope repo list<cr>
" Netrw settings
nnoremap <leader>dd :Lexplore %:p:h<CR>
nnoremap <Leader>da :Lexplore<CR>
" Save buffer
nnoremap <leader>w :w<CR>
" Move screen to contain current line at the top
nnoremap <leader>d zt
nnoremap <leader>sv :source ${HOME}/.config/nvim/init.vim<CR>
" jj in insert mode instead of ESC
inoremap jj <Esc>
inoremap jk <Esc>
" Zoom split windows
noremap Zz <c-w>_ \| <c-w>\|
noremap Zo <c-w>=
" Split navigation
nnoremap <S-L> <C-W><C-L>
nnoremap <S-H> <C-W><C-H>
nnoremap <S-U> <C-W><C-K>
nnoremap <S-J> <C-W><C-J>
"Neovim built in terminal settings
autocmd TermOpen term://* startinsert
command! -nargs=* T :split | resize 15 | terminal
command! -nargs=* VT vsplit | terminal <args>
tnoremap <Esc> <C-\><C-n>
"Floatterm settings
nnoremap   <silent><Leader>fl :FloatermNew<CR>
nnoremap   <silent><Leader>ft :FloatermToggle<CR>
nnoremap   <silent><Leader>fs :FloatermShow<CR>
nnoremap   <silent><Leader>fh :FloatermHide<CR>
nnoremap   <silent><Leader>fn :FloatermNext<CR>
nnoremap   <silent><Leader>fc :FloatermKill<CR>
" add relative number movements to the jump list 
nnoremap <expr> k (v:count1 > 1 ? "m'" . v:count1 : '') . 'k' 
nnoremap <expr> j (v:count1 > 1 ? "m'" . v:count1 : '') . 'j'

" PROGRAMMING
" -----------
"
" Use `[g` and `]g` to navigate diagnostics
" Use `:CocDiagnostics` to get all diagnostics of current buffer in location list.
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)
" GoTo code navigation.
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gimp <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)
" Symbol renaming.
nmap <leader>rn <Plug>(coc-rename)
" Formatting selected code.
xmap <leader>fo <Plug>(coc-format-selected)
nmap <leader>fo <Plug>(coc-format-selected)
" Applying codeAction to the selected region.
" Example: `<leader>aap` for current paragraph
xmap <leader>a <Plug>(coc-codeaction-selected)
nmap <leader>a <Plug>(coc-codeaction-selected)
" Remap keys for applying codeAction to the current buffer.
nmap <leader>ac <Plug>(coc-codeaction)
" Apply AutoFix to problem on the current line.
nmap <leader>qf <Plug>(coc-fix-current)
" Map function and class text objects
" NOTE: Requires 'textDocument.documentSymbol' support from the language server.
xmap if <Plug>(coc-funcobj-i)
omap if <Plug>(coc-funcobj-i)
xmap af <Plug>(coc-funcobj-a)
omap af <Plug>(coc-funcobj-a)
" Use CTRL-S for selections ranges.
" Requires 'textDocument/selectionRange' support of language server.
nmap <silent> <C-s> <Plug>(coc-range-select)
xmap <silent> <C-s> <Plug>(coc-range-select)
" Use K to show documentation in preview window.
nnoremap <silent> K :call <SID>show_documentation()<CR>
" vsnip settings
" Expand
imap <expr> <C-j>   vsnip#expandable()  ? '<Plug>(vsnip-expand)'         : '<C-j>'
smap <expr> <C-j>   vsnip#expandable()  ? '<Plug>(vsnip-expand)'         : '<C-j>'

" Expand or jump
imap <expr> <C-l>   vsnip#available(1)  ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>'
smap <expr> <C-l>   vsnip#available(1)  ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>'
" Select or cut text to use as $TM_SELECTED_TEXT in the next snippet.
" See https://github.com/hrsh7th/vim-vsnip/pull/50
nmap <leader>t <Plug>(vsnip-select-text)
xmap <leader>t <Plug>(vsnip-select-text)
nmap <leader>tc <Plug>(vsnip-cut-text)
xmap <leader>tc <Plug>(vsnip-cut-text)
" Use tab for trigger completion with characters ahead and navigate.
" NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
" other plugin before putting this into your config.
inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"
function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  elseif (coc#rpc#ready())
    call CocActionAsync('doHover')
  else
    execute '!' . &keywordprg . " " . expand('<cword>')
  endif
endfunction
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
" This was causing E109 Missing ':' after ?
" inoremap <silent><expr> <cr> pumvisible() ? : coc#_select_confirm()
" Git mappings
command GitDiff execute  "w !git diff --no-index -- % -"
" Add `:Format` command to format current buffer.
command! -nargs=0 Format :call CocAction('format')
" Add `:Fold` comand to fold current buffer.
command! -nargs=? Fold :call     CocAction('fold', <f-args>)
" Add `:OR` command for organize imports of the current buffer.
command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organizeImport')
" Use <Ctrl-F> to format documents with prettier
command! -nargs=0 Prettier :CocCommand prettier.formatFile
noremap <C-F> :Prettier<CR>

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
Plugin 'nvim-telescope/telescope.nvim'
Plugin 'nvim-telescope/telescope-fzf-native.nvim', { 'do': 'make' }
Plugin 'voldikss/vim-floaterm'
Plugin 'easymotion/vim-easymotion'
Plugin 'rafamadriz/friendly-snippets'
Plugin 'cljoly/telescope-repo.nvim'
Plugin 'kdheepak/lazygit.nvim'
Plugin 'karoliskoncevicius/vim-sendtowindow'
Plugin 'jpalardy/vim-slime'
Plugin 'ldelossa/gh.nvim'
" Editing related
Plugin 'Raimondi/delimitMate'
Plugin 'godlygeek/tabular'
Plugin 'plasticboy/vim-markdown'
Plugin 'mattn/webapi-vim'
Plugin 'Yggdroot/indentLine'
Plugin 'tpope/vim-surround'
Plugin 'mattn/emmet-vim'
Plugin 'wellle/targets.vim'
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
Plugin 'preservim/nerdcommenter'
" Programming
Plugin 'majutsushi/tagbar'
Plugin 'hashivim/vim-terraform'
Plugin 'fatih/vim-go'
Plugin 'neoclide/coc.nvim', {'branch': 'release'}
Plugin 'rhysd/vim-clang-format'
Plugin 'dense-analysis/ale'
Plugin 'tpope/vim-fugitive'
Plugin 'airblade/vim-gitgutter'
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

" AUTOGROUPS
" ----------
"
augroup mygroup
  autocmd!
  " Setup formatexpr specified filetype(s).
  autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
  " Update signature help on jump placeholder.
  autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
augroup end
" indent for special file
autocmd FileType c,cpp setlocal expandtab shiftwidth=2 softtabstop=2 cindent
autocmd FileType python setlocal expandtab shiftwidth=4 softtabstop=4 autoindent
autocmd FileType yaml setlocal ts=2 sts=2 sw=4 expandtab
autocmd FileType markdown setlocal expandtab shiftwidth=4 softtabstop=4 autoindent
" Highlight the symbol and its references when holding the cursor.
autocmd CursorHold * silent! call CocActionAsync('highlight')
" autoformat
augroup autoformat_settings
  autocmd FileType c,cpp,proto,javascript setlocal equalprg=clang-format
  autocmd FileType python AutoFormatBuffer yapf
augroup end
augroup last_cursor_position
  autocmd!
  autocmd BufReadPost *
    \ if line("'\"") > 1 && line("'\"") <= line("$") && &ft !~# 'commit' | execute "normal! g`\"zvzz" | endif
augroup end

" PLUGIN SETTINGS
" ---------------
"
" Add (Neo)Vim's native statusline support.
" NOTE: Please see `:h coc-status` for integrations with external plugins that
" provide custom statusline: lightline.vim, vim-airline.
set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}
" Color name (:help cterm-colors) or ANSI code
let g:limelight_conceal_ctermfg = 'gray'
let g:limelight_conceal_ctermfg = 240
let g:sendtowindow_use_defaults=0
" there are some defaults for image directory and image name, you can change them
let g:mdip_imgdir = '_media'
let g:mdip_imgname = 'image'
let g:plantuml_previewer#viewer_path = '~/.vim/bundle/plantuml-previewer.vim/viewer'
"let g:plantuml_previewer#viewer_path = '/Users/piotr/.vim/bundle/plantuml-previewer.vim/viewer'
let g:plantuml_previewer#debug_mode = 0
" setup custom emmet snippets
let g:user_emmet_settings = webapi#json#decode(join(readfile(expand('~/.snippets_custom.json')), "\n"))
let g:indentLine_char = '⦙'
" Setup for slime
let g:slime_target = "tmux"
let g:slime_default_config = {"socket_name": "default", "target_pane": "{last}"}
" setup for netrw
let g:netrw_winsize = 30
let g:netrw_banner = 0
let g:netrw_keepdir = 0
" setup for markdown snippet
let g:vim_markdown_folding_disabled = 1
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
let g:indentLine_char = '|'
set tags=./tags,tags;$HOME
"source ~/cscope_maps.vim
let g:go_fmt_command = "goimports"
let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_structs = 1
let g:go_highlight_interfaces = 1
let g:go_highlight_operators = 1
" MarkdownPreview settings
let g:mkdp_browser = '/usr/bin/google-chrome'
let g:mkdp_echo_preview_url = 0
