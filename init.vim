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

function! WinMoveA(key)
    let t:curwin = winnr()
    exec "wincmd ".a:key
    if (t:curwin == winnr())
        if (match(a:key,'[DownUp]'))
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

nnoremap <silent> <A-Left> :call WinMoveA('h')<CR>
nnoremap <silent> <A-Down> :call WinMoveA('j')<CR>
nnoremap <silent> <A-Up> :call WinMoveA('k')<CR>
nnoremap <silent> <A-RIght> :call WinMoveA('l')<CR>
