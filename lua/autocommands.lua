local sysname = vim.loop.os_uname().sysname
local api = vim.api

local indentSettings = vim.api.nvim_create_augroup("IndentSettings", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  command = "setlocal expandtab shiftwidth=2 softtabstop=2 cindent",
  group = indentSettings,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "yaml" },
  command = "setlocal ts=2 sts=2 sw=2 expandtab",
  group = indentSettings,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "python" },
  command = "setlocal expandtab shiftwidth=4 softtabstop=4 autoindent",
  group = indentSettings,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "go" },
  command = "set foldmethod=manual",
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "go" },
  command = "nmap <buffer><silent> <leader>fld :%g/ {/normal! zf%<CR>",
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown" },
  command = "nmap <buffer><silent> <leader>p :call mdip#MarkdownClipboardImage()<CR>",
})

api.nvim_exec(
  [[
    augroup fileTypes
     autocmd FileType lua setlocal foldmethod=marker
     autocmd FileType go setlocal foldmethod=expr
     autocmd BufRead,BufNewFile .envrc set filetype=sh
    augroup end
  ]], false
)

api.nvim_exec(
  [[
    augroup helpers
     autocmd!
     autocmd TermOpen term://* startinsert
     autocmd BufEnter * silent! lcd %:p:h
    augroup end
  ]], false
)

api.nvim_exec(
  [[
    augroup plantuml
     autocmd BufWritePost *.puml silent! !java -DPLANTUML_LIMIT_SIZE=8192 -jar /usr/local/bin/plantuml.jar -tsvg <afile> -o ./rendered
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
     autocmd BufWritePost plugins.lua source <afile> | PackerSync
    augroup end
  ]]

vim.cmd
[[
 augroup MKDX
   au!
   au FileType markdown so $HOME/.vim/bundle/mkdx/ftplugin/markdown.vim
 augroup END
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
       ]], false)
end
require('telescope').setup {
  --  defaults   = {},
  --  pickers    = {},
  extensions = {
    file_browser = {}
  }
}
-- User commands {{{
-- Format with default CocAction
vim.api.nvim_create_user_command(
  'Format',
  "call CocAction('format')",
  { bang = true }
)

-- Add -name: to composition resources
vim.api.nvim_create_user_command(
  'AddNames',
  'g/apiVersion: \\(apiextensions\\|platform-composites\\)\\@!/normal!O- name:',
  { bang = false }
)

--Open Buildin terminal vertical mode
vim.api.nvim_create_user_command(
  'VT',
  "vsplit | terminal bash -c \"cd %:p:h;zsh\"",
  { bang = false, nargs = '*' }
)

--Open Buildin terminal
vim.api.nvim_create_user_command(
  'T',
  "split | resize 15 | terminal bash -c \"cd %:p:h;zsh\"",
  { bang = true, nargs = '*' }
)

--Execute shell command in a read-only scratchpad buffer
vim.api.nvim_create_user_command(
  'R',
  "new | setlocal buftype=nofile bufhidden=hide noswapfile | r !<args>",
  { bang = false, nargs = '*', complete = 'shellcmd' }
)

--Get diff for current file
vim.api.nvim_create_user_command(
  'Gdiff',
  "execute  'w !git diff --no-index -- % -'",
  { bang = false }
)

--Get diff for current file
vim.api.nvim_create_user_command(
  'Pretty',
  "CocCommand prettier.formatFile",
  { bang = true }
)

vim.cmd [[
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
]]
-- }}}
