local api = vim.api

api.nvim_exec(
  [[
    augroup intendation
     autocmd FileType c,cpp setlocal expandtab shiftwidth=2 softtabstop=2 cindent
     autocmd FileType python setlocal expandtab shiftwidth=4 softtabstop=4 autoindent
     autocmd FileType yaml setlocal ts=2 sts=2 sw=4 expandtab
     autocmd FileType markdown setlocal expandtab shiftwidth=4 softtabstop=4 autoindent
    augroup end
  ]], false
)

api.nvim_exec(
  [[
    augroup cocHelpers
     autocmd!
     autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
     autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
     autocmd CursorHold * silent! call CocActionAsync('highlight')
    augroup end
  ]], false
)

api.nvim_exec(
  [[
    augroup autoformat_settings
     autocmd FileType c,cpp,proto,javascript setlocal equalprg=clang-format
     autocmd FileType python AutoFormatBuffer yapf
    augroup end
  ]], false
)

api.nvim_exec(
  [[
    augroup last_cursor_position
     autocmd!
     autocmd BufReadPost *
       \ if line("'\"") > 1 && line("'\"") <= line("$") && &ft !~# 'commit' | execute "normal! g`\"zvzz" | endif
    augroup end
  ]], false
)
-- Compile packages on add
vim.cmd 
  [[
    augroup Packer
     autocmd!
     autocmd BufWritePost plugins.lua PackerCompile
    augroup end
  ]]
