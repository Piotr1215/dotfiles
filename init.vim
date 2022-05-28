lua require('settings')
lua require('mappings')
lua require('plugins')
lua require('telescope')
lua require('autogroups')
lua require('lspsetup')

" Declare global variable to mark system
let uname = system('uname -s')

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

" Use tab for trigger completion with characters ahead and navigate.
" NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
" other plugin before putting this into your config.
"inoremap <silent><expr> <TAB>
"      \ pumvisible() ? "\<C-n>" :
"      \ <SID>check_back_space() ? "\<TAB>" :
"      \ coc#refresh()
"inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"
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
set completefunc=emoji#complete

" *** COLOR_SCHEMES ***
let g:lightline = {
      \ 'colorscheme': 'PaperColor',
      \ }

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
