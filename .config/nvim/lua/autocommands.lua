local sysname = vim.loop.os_uname().sysname
local api = vim.api

local indentSettings = vim.api.nvim_create_augroup("IndentSettings", { clear = true })
local goSettings = vim.api.nvim_create_augroup("Go Settings", { clear = true })
local yamlSettings = vim.api.nvim_create_augroup("Yaml Settings", { clear = true })

vim.api.nvim_create_user_command("Pretty", "Prettier", { bang = true })

vim.api.nvim_create_user_command("Browse", function(opts)
  vim.fn.system { "xdg-open", opts.fargs[1] }
end, { nargs = 1 })

vim.cmd [[
  autocmd BufWritePost mappings.lua normal! mM
]]

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

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = { "*.go" },
  command = ":silent! Neoformat",
  group = goSettings,
})

vim.api.nvim_create_user_command("StartEmpty", function()
  vim.cmd "enew"
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "hide"
  vim.bo.swapfile = false
end, {})

-- Function to dynamically set up Vale based on the file's directory
vim.api.nvim_create_autocmd("FileType", {
  pattern = "*",
  callback = function()
    vim.opt_local.formatoptions:remove "o"
  end,
})

local function toggle_formatoptions_o()
  local current_formatoptions = vim.opt.formatoptions:get()
  if vim.tbl_contains(current_formatoptions, "o") then
    vim.opt.formatoptions:remove "o"
    print "Removed 'o' from formatoptions"
  else
    vim.opt.formatoptions:append "o"
    print "Added 'o' to formatoptions"
  end
end

vim.api.nvim_create_user_command("TmuxLayout", function()
  local layout = vim.fn.system "tmux list-windows | sed -n 's/.*layout \\(.*\\)] @.*/\\1/p'"
  layout = layout:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
  vim.api.nvim_put({ "      layout: " .. layout }, "l", true, true)
end, {})

-- Create a user command to toggle formatoptions
vim.api.nvim_create_user_command("ToggleFormatoptions", toggle_formatoptions_o, {})

local function dynamicValeSetup()
  -- Get the current file's directory
  local file_path = vim.fn.expand "%:p:h"

  -- Default vale_config_path
  local default_vale_config_path = "$HOME/dev/vale/.vale.ini"
  local vale_config_path = default_vale_config_path

  -- Check if the current file is inside the crossplane-docs/content directory
  if string.match(file_path, "crossplane%-docs/content") then
    -- Update vale_config_path for crossplane-docs content
    default_vale_config_path = "$HOME/dev/crossplane-docs/utils/vale/.vale.ini"
    vale_config_path = default_vale_config_path
  end

  -- Check if .vale.ini exists in the current directory
  local current_dir_vale_path = file_path .. "/.vale.ini"
  if vim.fn.filereadable(current_dir_vale_path) == 1 then
    vale_config_path = current_dir_vale_path
  end

  -- Configure Vale with the determined vale_config_path
  require("vale").setup {
    bin = "/usr/local/bin/vale",
    vale_config_path = vale_config_path,
  }
end

-- Autocommand to configure Vale on entering a buffer or when the filetype is markdown
vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
  pattern = "*.md",
  callback = function()
    dynamicValeSetup()
  end,
})
-- Run Vale on markdown files in crossplane-docs
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.md",
  callback = function(args)
    local file_path = vim.fn.getcwd()
    if string.match(file_path, "crossplane%-docs/content") then
      local current_dir = vim.fn.getcwd()
      vim.cmd "lcd %:p:h"
      vim.cmd ":silent! Vale"
      vim.cmd("lcd " .. current_dir)
    end
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  command = "setlocal expandtab shiftwidth=2 softtabstop=2 cindent",
  group = indentSettings,
})

vim.api.nvim_create_user_command("WS", function()
  vim.cmd "write | source %"
end, { bang = false })

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "python" },
  command = "setlocal expandtab shiftwidth=4 softtabstop=4 autoindent",
  group = indentSettings,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.yaml",
  callback = function()
    vim.cmd "silent Neoformat"
  end,
  group = yamlSettings,
})

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.hurl",
  callback = function()
    vim.opt.filetype = "hurl"
  end,
})

-- vim.api.nvim_create_autocmd("BufWritePost", {
-- pattern = "*.md",
-- callback = function()
-- local file_path = vim.fn.expand "%:p" -- Get the full path of the current file
-- if not string.match(file_path, "crossplane%-docs") then
-- vim.cmd "silent Neoformat"
-- end
-- end,
-- })

function StyluaFormat()
  local current_dir = vim.fn.getcwd()
  local file_dir = vim.fn.fnamemodify(vim.fn.expand "%:p", ":h")
  vim.cmd("cd " .. file_dir)
  vim.cmd("silent! !stylua --search-parent-directories " .. vim.fn.expand "%:p")
  vim.cmd("cd " .. current_dir)
end
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.lua",
  callback = function()
    StyluaFormat()
  end,
  desc = "Auto-format Lua files with Stylua",
})

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
  vim.cmd "new"
  vim.cmd "setlocal buftype=nofile bufhidden=hide noswapfile"

  -- Execute the shell command and capture its output in the buffer
  vim.cmd("r !" .. args)

  -- Get the buffer number of the current (scratch) buffer
  local buf = vim.api.nvim_get_current_buf()

  -- Set the 'q' key to exit the buffer in the scratch buffer
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":q!<CR>", { noremap = true, silent = true })
end

-- Create a user command 'R' to execute your Lua function, passing along any arguments
vim.api.nvim_create_user_command(
  "R",
  "lua create_scratch_buffer(<q-args>)",
  { bang = false, nargs = "*", complete = "shellcmd" }
)

-- Highlighting when yanking text
vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight yanked text",
  pattern = "*",
  callback = function()
    vim.highlight.on_yank { higroup = "IncSearch", timeout = 250 }
  end,
})

--Get diff for current file
vim.api.nvim_create_user_command("Gdiff", "execute  'w !git diff --no-index -- % -'", { bang = false })

vim.api.nvim_create_user_command("Ghistory", function()
  -- Get the current file path
  local file_path = vim.api.nvim_buf_get_name(0)

  -- Run git diff and capture the output
  local handle = io.popen("git log -p --all -- " .. file_path, "r")
  local result = handle:read "*a"
  handle:close()

  -- Split the output into lines for the floating window
  local content = {}
  for line in result:gmatch "([^\n]*)\n?" do
    table.insert(content, line)
  end

  -- Display the result in a floating scratch buffer
  require("user_functions.utils").create_floating_scratch(content)
end, { bang = false, desc = "Show git history for the current file" })

vim.api.nvim_create_user_command("Gdiffu", function()
  -- Save the current buffer
  vim.cmd "w"

  -- Get the current file path
  local file_path = vim.api.nvim_buf_get_name(0)

  -- Run git diff and capture the output
  local handle = io.popen("git diff --unified=0 -- " .. file_path)
  local result = handle:read "*a"
  handle:close()

  -- Split the output into lines for the floating window
  local content = {}
  for line in result:gmatch "([^\n]*)\n?" do
    table.insert(content, line)
  end

  -- Display the result in a floating scratch buffer
  require("user_functions.utils").create_floating_scratch(content)
end, { bang = false })

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
