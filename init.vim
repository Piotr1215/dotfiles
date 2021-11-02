set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath
source ~/.vimrc

set clipboard+=unnamedplus

if !has('nvim')
 set ttymouse=xterm2
endif

if exists(':tnoremap')                                                                                                                                                                                                           
 tnoremap <Esc> <C-\><C-n>
endif
