lua require('settings')
lua require('plugins')
lua require('mappings')
lua require('telescope')
lua require('autogroups')
lua require('lspsetup')

" Declare global variable to mark system
let uname = system('uname -s')

if uname =~ 'Linux'
  nnoremap ö /
  inoremap ö /
endif

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

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction
