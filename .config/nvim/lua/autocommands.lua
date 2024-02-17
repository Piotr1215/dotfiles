local sysname = vim.loop.os_uname().sysname
local api = vim.api

local indentSettings = vim.api.nvim_create_augroup("IndentSettings", { clear = true })
local goSettings = vim.api.nvim_create_augroup("Go Settings", { clear = true })

vim.api.nvim_create_user_command("Pretty", "Prettier", { bang = true })

vim.api.nvim_create_user_command(
  'Browse',
  function(opts)
    vim.fn.system { 'xdg-open', opts.fargs[1] }
  end,
  { nargs = 1 }
)

-- vim.api.nvim_create_autocmd("BufWritePre", {
-- pattern = "*.go",
-- callback = function()
-- vim.lsp.buf.code_action { context = { only = { "source.organizeImports" } }, apply = true }
-- end,
-- })

vim.cmd([[
  autocmd BufWritePost mappings.lua normal! mM
]])

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "go" },
  command = "nmap <buffer><silent> <leader>fld :%g/ {/normal! zf%<CR>",
  group = goSettings,
})
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = { "*test*.go" },
  command = ":silent! GoTestFile",
  group = goSettings,
})


-- Run Vale on markdown files in crossplane-docs
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.md",
  callback = function(args)
    local file_path = vim.fn.getcwd()
    if string.match(file_path, "crossplane%-docs/content") then
      local current_dir = vim.fn.getcwd()
      vim.cmd("lcd %:p:h")
      vim.cmd(":silent! Vale")
      vim.cmd("lcd " .. current_dir)
    end
  end,
})

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
  pattern = { "python" },
  command = "setlocal expandtab shiftwidth=4 softtabstop=4 autoindent",
  group = indentSettings,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.md",
  callback = function()
    local file_path = vim.fn.expand('%:p') -- Get the full path of the current file
    if not string.match(file_path, "crossplane%-docs") then
      vim.cmd("silent Neoformat")
    end
  end,
})

function StyluaFormat()
  local current_dir = vim.fn.getcwd()
  local file_dir = vim.fn.fnamemodify(vim.fn.expand "%:p", ":h")
  vim.cmd("cd " .. file_dir)
  vim.cmd("silent! !stylua --search-parent-directories " .. vim.fn.expand "%:p")
  vim.cmd("cd " .. current_dir)
end

vim.api.nvim_create_autocmd({ "bufwritepost" }, {
  pattern = { "*.sh" },
  command = "silent! !shfmt -l -w %",
})

vim.cmd [[
  command! TMarkn execute "r !~/dev/dotfiles/scripts/__list_tasks_as_markdown.pl '+next'"
]]
vim.cmd [[
  command! ClearQF call setqflist([])
]]
api.nvim_exec(
  [[
    augroup fileTypes
     autocmd BufRead,BufNewFile .envrc set filetype=sh
    augroup end
  ]],
  false
)

api.nvim_exec(
  [[
    augroup helpers
     autocmd!
     autocmd TermOpen term://* startinsert
     autocmd BufEnter * silent! lcd %:p:h
    augroup end
  ]],
  false
)

api.nvim_exec(
  [[
    augroup plantuml
     autocmd BufWritePost *.puml silent! !java -DPLANTUML_LIMIT_SIZE=8192 -jar /usr/local/bin/plantuml.jar -tsvg <afile> -o ./rendered
    augroup end
  ]],
  false
)

api.nvim_exec(
  [[
    augroup last_cursor_position
     autocmd!
     autocmd BufReadPost *
       \ if line("'\"") > 1 && line("'\"") <= line("$") && &ft !~# 'commit' | execute "normal! g`\"zvzz" | endif
    augroup end
  ]],
  false
)
-- Compile packages on add
vim.cmd [[
    augroup Packer
     autocmd!
     autocmd BufWritePost plugins.lua source <afile> | PackerSync
    augroup end
  ]]

if sysname == "Darwin" then
  api.nvim_exec(
    [[
         augroup plant_folder
          autocmd FileType plantuml let g:plantuml_previewer#plantuml_jar_path = get(
              \  matchlist(system('cat `which plantuml` | grep plantuml.jar'), '\v.*\s[''"]?(\S+plantuml\.jar).*'),
              \  1,
              \  0
              \)
         augroup end
       ]],
    false
  )
end

-- Add -name: to composition resources
vim.api.nvim_create_user_command(
  "AddNames",
  "g/apiVersion: \\(apiextensions\\|platform-composites\\)\\@!/normal!O- name:",
  { bang = false }
)

--Open Buildin terminal vertical mode
vim.api.nvim_create_user_command("VT", 'vsplit | terminal bash -c "cd %:p:h;zsh"', { bang = false, nargs = "*" })

--Open Buildin terminal
vim.api.nvim_create_user_command(
  "T",
  'split | resize 15 | terminal bash -c "cd %:p:h;zsh"',
  { bang = true, nargs = "*" }
)

-- Define a Lua function to create the scratch buffer, execute the shell command, and set the keymap
function create_scratch_buffer(args)
  -- Create a new scratch buffer
  vim.cmd("new")
  vim.cmd("setlocal buftype=nofile bufhidden=hide noswapfile")

  -- Execute the shell command and capture its output in the buffer
  vim.cmd("r !" .. args)

  -- Get the buffer number of the current (scratch) buffer
  local buf = vim.api.nvim_get_current_buf()

  -- Set the 'q' key to exit the buffer in the scratch buffer
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':q!<CR>', { noremap = true, silent = true })
end

-- Create a user command 'R' to execute your Lua function, passing along any arguments
vim.api.nvim_create_user_command(
  "R",
  "lua create_scratch_buffer(<q-args>)",
  { bang = false, nargs = "*", complete = "shellcmd" }
)


--Get diff for current file
vim.api.nvim_create_user_command("Gdiff", "execute  'w !git diff --no-index -- % -'", { bang = false })

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
