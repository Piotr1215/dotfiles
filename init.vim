lua require('settings')
lua require('plugins')
lua require('mappings')
lua require('telescopesetup')
lua require('autogroups')
lua require('lspsetup')

function! WinMove(key)
    let t:curwin = winnr()
    exec "wincmd ".a:key
    if (t:curwin == winnr())
        if (match(a:key,'[jk]'))
            wincmd v
        else
            wincmd s
        endif
        exec "wincmd ".a:key
    endif
endfunction

nnoremap <silent> <C-h> :call WinMove('h')<CR>
nnoremap <silent> <C-j> :call WinMove('j')<CR>
nnoremap <silent> <C-k> :call WinMove('k')<CR>
nnoremap <silent> <C-l> :call WinMove('l')<CR>

nnoremap <silent> <A-h> :call WinMove('h')<CR>
nnoremap <silent> <A-j> :call WinMove('j')<CR>
nnoremap <silent> <A-k> :call WinMove('k')<CR>
nnoremap <silent> <A-l> :call WinMove('l')<CR>
