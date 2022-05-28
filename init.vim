syntax enable
syntax on
filetype on
filetype plugin indent on

lua require('settings')
lua require('mappings')
lua require('plugins')
lua require('telescope')
lua require('autogroups')

" Declare global variable to mark system
let uname = system('uname -s')
map ` <Nop>

if uname =~ 'Linux'
  nnoremap ö /
  inoremap ö /
endif

let @q = "wys$)lvt S'f i,wvt)S'^"

" MARKDOWN
" --------
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
"Neovim built in terminal settings
autocmd TermOpen term://* startinsert
command! -nargs=* T :split | resize 15 | terminal
command! -nargs=* VT vsplit | terminal <args>
tnoremap <Esc> <C-\><C-n>
" add relative number movements to the jump list 
nnoremap <expr> k (v:count1 > 1 ? "m'" . v:count1 : '') . 'k' 
nnoremap <expr> j (v:count1 > 1 ? "m'" . v:count1 : '') . 'j'

" PROGRAMMING
" -----------
"
" Use `[g` and `]g` to navigate diagnostics
" Use `:CocDiagnostics` to get all diagnostics of current buffer in location list.
"nmap <silent> [g <Plug>(coc-diagnostic-prev)
"nmap <silent> ]g <Plug>(coc-diagnostic-next)
"" GoTo code navigation.
"nmap <silent> gd <Plug>(coc-definition)
"nmap <silent> gy <Plug>(coc-type-definition)
"nmap <silent> gimp <Plug>(coc-implementation)
"nmap <silent> gr <Plug>(coc-references)
"" Symbol renaming.
"nmap <leader>rn <Plug>(coc-rename)
"" Formatting selected code.
"xmap <leader>fo <Plug>(coc-format-selected)
"nmap <leader>fo <Plug>(coc-format-selected)
"" Applying codeAction to the selected region.
"" Example: `<leader>aap` for current paragraph
"xmap <leader>a <Plug>(coc-codeaction-selected)
"nmap <leader>a <Plug>(coc-codeaction-selected)
"" Remap keys for applying codeAction to the current buffer.
"nmap <leader>ac <Plug>(coc-codeaction)
"" Apply AutoFix to problem on the current line.
"nmap <leader>qf <Plug>(coc-fix-current)
"" Map function and class text objects
"" NOTE: Requires 'textDocument.documentSymbol' support from the language server.
"xmap if <Plug>(coc-funcobj-i)
"omap if <Plug>(coc-funcobj-i)
"xmap af <Plug>(coc-funcobj-a)
"omap af <Plug>(coc-funcobj-a)
"" Use CTRL-S for selections ranges.
"" Requires 'textDocument/selectionRange' support of language server.
"nmap <silent> <C-s> <Plug>(coc-range-select)
"xmap <silent> <C-s> <Plug>(coc-range-select)
"" Use K to show documentation in preview window.


nnoremap <silent> K :call <SID>show_documentation()<CR>


"" vsnip settings
"" Expand
"imap <expr> <C-j>   vsnip#expandable()  ? '<Plug>(vsnip-expand)'         : '<C-j>'
"smap <expr> <C-j>   vsnip#expandable()  ? '<Plug>(vsnip-expand)'         : '<C-j>'
"
"" Expand or jump
"imap <expr> <C-l>   vsnip#available(1)  ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>'
"smap <expr> <C-l>   vsnip#available(1)  ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>'
"" Select or cut text to use as $TM_SELECTED_TEXT in the next snippet.
"" See https://github.com/hrsh7th/vim-vsnip/pull/50
"nmap <leader>t <Plug>(vsnip-select-text)
"xmap <leader>t <Plug>(vsnip-select-text)
"nmap <leader>tc <Plug>(vsnip-cut-text)
"xmap <leader>tc <Plug>(vsnip-cut-text)
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
" Add `:Fold` comand to fold current buffer.
command! -nargs=? Fold :call     CocAction('fold', <f-args>)
" Add `:OR` command for organize imports of the current buffer.
command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organizeImport')

set completefunc=emoji#complete

" *** COLOR_SCHEMES ***
set t_Co=256
set background=dark
let g:lightline = {
      \ 'colorscheme': 'PaperColor',
      \ }
colorscheme PaperColor

" AUTOGROUPS
" Highlight the symbol and its references when holding the cursor.
autocmd CursorHold * silent! call CocActionAsync('highlight')

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
