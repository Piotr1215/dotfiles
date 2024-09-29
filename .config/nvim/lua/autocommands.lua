-- Variables and Initial Settings
local sysname = vim.loop.os_uname().sysname
local api = vim.api

-- Autocmd Groups
local indentSettings = api.nvim_create_augroup("IndentSettings", { clear = true })
local yamlSettings = api.nvim_create_augroup("YamlSettings", { clear = true })
local fileTypeSettings = api.nvim_create_augroup("FileTypeSettings", { clear = true })
local helpersGroup = api.nvim_create_augroup("Helpers", { clear = true })
local plantumlGroup = api.nvim_create_augroup("PlantUML", { clear = true })
local lastCursorGroup = api.nvim_create_augroup("LastCursorPosition", { clear = true })
local formattingGroup = api.nvim_create_augroup("AutoFormatting", { clear = true })
local highlightingGroup = api.nvim_create_augroup("Highlighting", { clear = true })

-- Functions
local function stylua_format()
  local file_path = vim.fn.expand "%:p"
  vim.fn.jobstart({ "stylua", "--search-parent-directories", file_path }, { detach = true })
end

local function shfmt_format()
  local file_path = vim.fn.expand "%"
  vim.fn.jobstart({ "shfmt", "-l", "-w", file_path }, { detach = true })
end

local function generate_plantuml()
  local afile = vim.fn.expand "<afile>"
  vim.fn.jobstart({
    "java",
    "-DPLANTUML_LIMIT_SIZE=8192",
    "-jar",
    "/usr/local/bin/plantuml.jar",
    "-tsvg",
    afile,
    "-o",
    "./rendered",
  }, { detach = true })
end

-- User Commands
vim.api.nvim_create_user_command("ClearQF", function()
  vim.fn.setqflist {}
end, {})

vim.api.nvim_create_user_command("Gdiff", function()
  vim.cmd 'execute "w !git diff --no-index -- % -"'
end, {})

vim.api.nvim_create_user_command("Gdiffu", function()
  vim.cmd "w"
  local file_path = vim.fn.expand "%"
  local result = vim.fn.systemlist { "git", "diff", "--unified=0", "--", file_path }
  require("user_functions.utils").create_floating_scratch(result)
end, {})

vim.api.nvim_create_user_command("Ghistory", function()
  local file_path = vim.fn.expand "%"
  local result = vim.fn.systemlist { "git", "log", "-p", "--all", "--", file_path }
  require("user_functions.utils").create_floating_scratch(result)
end, { desc = "Show git history for the current file" })

vim.api.nvim_create_user_command("R", function(opts)
  vim.cmd "new"
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "hide"
  vim.bo.swapfile = false
  vim.fn.termopen(opts.args)
  vim.api.nvim_buf_set_keymap(0, "n", "q", ":q!<CR>", { noremap = true, silent = true })
end, { nargs = "+", complete = "shellcmd" })

vim.api.nvim_create_user_command("T", function()
  vim.cmd "split"
  vim.cmd "resize 15"
  vim.fn.termopen("zsh", { cwd = vim.fn.expand "%:p:h" })
end, {})

vim.api.nvim_create_user_command("TMarkn", function()
  vim.cmd [[execute "r !~/dev/dotfiles/scripts/__list_tasks_as_markdown.pl '+next'" ]]
end, {})

vim.api.nvim_create_user_command("VT", function()
  vim.cmd "vsplit"
  vim.fn.termopen("zsh", { cwd = vim.fn.expand "%:p:h" })
end, {})

-- Add this to your Neovim configuration (init.lua)
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local search_value = os.getenv "NVIM_SEARCH_REGISTRY"
    if search_value and #search_value > 0 then
      vim.fn.setreg("/", search_value)
      print("Search register set to: " .. search_value)
    end
  end,
})
-- Indentation Settings
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  callback = function()
    vim.opt_local.expandtab = true
    vim.opt_local.shiftwidth = 2
    vim.opt_local.softtabstop = 2
    vim.opt_local.cindent = true
  end,
  group = indentSettings,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.opt_local.expandtab = true
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 4
    vim.opt_local.autoindent = true
  end,
  group = indentSettings,
})

-- YAML Settings
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.yaml",
  callback = function()
    vim.cmd "silent! Neoformat"
  end,
  group = yamlSettings,
})

-- File Type Settings
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = ".envrc",
  callback = function()
    vim.bo.filetype = "sh"
  end,
  group = fileTypeSettings,
})

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.hurl",
  callback = function()
    vim.bo.filetype = "hurl"
  end,
  group = fileTypeSettings,
})

-- Helper Autocmds
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*",
  callback = function()
    vim.cmd "silent! lcd %:p:h"
  end,
  group = helpersGroup,
})

-- PlantUML Autocmds
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.puml",
  callback = generate_plantuml,
  group = plantumlGroup,
})

if sysname == "Darwin" then
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "plantuml",
    callback = function()
      local plantuml_path = vim.fn.system "which plantuml"
      local jar_path = plantuml_path:match "(%S+plantuml%.jar)"
      vim.g.plantuml_previewer_plantuml_jar_path = jar_path
    end,
    group = plantumlGroup,
  })
end

-- Restore Last Cursor Position
vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = "*",
  callback = function()
    local last_pos = vim.fn.line [['"]]
    if last_pos > 1 and last_pos <= vim.fn.line "$" and vim.bo.filetype ~= "commit" then
      vim.cmd 'normal! g`"zvzz'
    end
  end,
  group = lastCursorGroup,
})

-- Auto Formatting
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.lua",
  callback = stylua_format,
  group = formattingGroup,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.sh",
  callback = shfmt_format,
  group = formattingGroup,
})

-- Highlight on Yank
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank { higroup = "IncSearch", timeout = 250 }
  end,
  group = highlightingGroup,
})

-- Remove 'o' from formatoptions when opening a new buffer
vim.api.nvim_create_autocmd("FileType", {
  pattern = "*",
  callback = function()
    vim.opt_local.formatoptions:remove "o"
  end,
})

-- Save mark 'M' when writing mappings.lua
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "mappings.lua",
  callback = function()
    vim.cmd "normal! mM"
  end,
})
