local api = vim.api

local sysname = vim.loop.os_uname().sysname

api.nvim_exec(
     [[
    augroup fileTypes
     autocmd FileType c,cpp setlocal expandtab shiftwidth=2 softtabstop=2 cindent
     autocmd FileType python setlocal expandtab shiftwidth=4 softtabstop=4 autoindent
     autocmd FileType yaml setlocal ts=2 sts=2 sw=4 expandtab
     autocmd FileType markdown setlocal expandtab shiftwidth=4 softtabstop=4 autoindent
     autocmd FileType markdown nmap <buffer><silent> <leader>p :call mdip#MarkdownClipboardImage()<CR>
    augroup end
  ]]  , false
)

api.nvim_exec(
     [[
    augroup helpers
     autocmd!
     autocmd TermOpen term://* startinsert
     autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
     autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
     autocmd CursorHold * silent! call CocActionAsync('highlight')
    augroup end
  ]]  , false
)

api.nvim_exec(
     [[
    augroup plantuml
     autocmd BufWritePost *.puml silent! !java -DPLANTUML_LIMIT_SIZE=8192 -jar /usr/local/bin/plantuml.jar -tsvg <afile> -o ./rendered
    augroup end
  ]]  , false
)

api.nvim_exec(
     [[
    augroup autoformat_settings
     autocmd FileType c,cpp,proto,javascript setlocal equalprg=clang-format
     autocmd FileType python AutoFormatBuffer yapf
    augroup end
  ]]  , false
)

api.nvim_exec(
     [[
    augroup last_cursor_position
     autocmd!
     autocmd BufReadPost *
       \ if line("'\"") > 1 && line("'\"") <= line("$") && &ft !~# 'commit' | execute "normal! g`\"zvzz" | endif
    augroup end
  ]]  , false
)
-- Compile packages on add
vim.cmd
[[
    augroup Packer
     autocmd!
     autocmd BufWritePost plugins.lua source <afile> | PackerCompile
    augroup end
  ]]

if sysname == 'Darwin' then
     api.nvim_exec(
     [[
         augroup plant_folder
          autocmd FileType plantuml let g:plantuml_previewer#plantuml_jar_path = get(
              \  matchlist(system('cat `which plantuml` | grep plantuml.jar'), '\v.*\s[''"]?(\S+plantuml\.jar).*'),
              \  1,
              \  0
              \)
         augroup end
       ]]   , false)
end
