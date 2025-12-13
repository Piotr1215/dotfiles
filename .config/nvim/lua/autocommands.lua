-- Variables and Initial Settings
local sysname = vim.uv.os_uname().sysname
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
local copilotGroup = api.nvim_create_augroup("Copilot", { clear = true })
local valeGroup = api.nvim_create_augroup("Vale", { clear = true })
local shellcheckGroup = api.nvim_create_augroup("Shellcheck", { clear = true })

-- Autocmds

api.nvim_create_autocmd("VimEnter", {
  group = copilotGroup,
  callback = function()
    local claude_entrypoint = vim.fn.environ().CLAUDE_CODE_ENTRYPOINT
    if claude_entrypoint == "cli" then
      vim.cmd "Copilot enable"
      -- Load Claude Code helpers
      require("claude_code").setup()
    else
      vim.cmd "Copilot disable"
    end
  end,
})

vim.api.nvim_create_autocmd({ "BufWritePost" }, {
  callback = function()
    require("lint").try_lint()
  end,
})

-- Shellcheck on save for shell scripts
api.nvim_create_autocmd("BufWritePost", {
  group = shellcheckGroup,
  pattern = { "*.sh", "*.bash" },
  callback = function()
    if vim.fn.executable "shellcheck" == 0 then
      return
    end

    local output = vim.fn.system("shellcheck -f gcc " .. vim.fn.shellescape(vim.fn.expand "%"))
    if vim.v.shell_error ~= 0 then
      vim.fn.setqflist({}, "r", {
        lines = vim.split(output, "\n"),
        title = "Shellcheck: " .. vim.fn.expand "%:t",
      })
    else
      vim.cmd "cclose"
    end
  end,
  desc = "Run shellcheck and populate quickfix on save",
})

api.nvim_create_autocmd({ "BufEnter", "BufRead" }, {
  pattern = ".nvimrc",
  callback = function()
    vim.bo.filetype = "lua"
  end,
})

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client:supports_method "textDocument/completion" then
      vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
    end
  end,
})

vim.api.nvim_create_autocmd("LspAttach", {
  pattern = "*.zshrc*",
  callback = function()
    vim.diagnostic.enable(false, { bufnr = 0 })
  end,
})

api.nvim_create_autocmd("VimEnter", {
  group = valeGroup,
  command = "LspStartVale",
  pattern = "*mdx",
})

-- Functions
local function stylua_format()
  local file_path = vim.fn.expand "%:p"
  vim.fn.system { "stylua", "--search-parent-directories", file_path }
  vim.cmd "e"
end

-- stylua: ignore start
---@diagnostic disable-next-line: unused-local
local shfmt_format = function()
  local file_path = vim.fn.expand "%:p"
  vim.fn.system { "shfmt", "-l", "-w", file_path }
  vim.cmd "e" -- Reload the file after formatting
end
-- stylua: ignore end
local _ = shfmt_format -- Reference to suppress unused warning

api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  group = formattingGroup,
  pattern = "*",
  callback = function()
    -- Skip if in command mode or command-line window
    if vim.fn.mode() ~= "c" and vim.fn.getcmdwintype() == "" then
      vim.cmd "checktime"
    end
  end,
})

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

vim.api.nvim_create_user_command("PrintEnv", function()
  vim.print(vim.fn.environ())
end, {})

vim.api.nvim_create_user_command("TmuxLayout", function()
  local layout = vim.fn.system "tmux list-windows | sed -n 's/.*layout \\(.*\\)] @.*/\\1/p'"
  layout = layout:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
  vim.api.nvim_put({ "      layout: " .. layout }, "l", true, true)
end, {})

vim.api.nvim_create_user_command("LowercaseFirstLetter", function(opts)
  local line1, line2 = opts.line1, opts.line2
  vim.cmd(string.format("%d,%ds/\\%%V\\<./\\l&/g", line1, line2))
end, { range = true })
vim.cmd "cnoreabbrev lc LowercaseFirstLetter"

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
  -- Expand % and # BEFORE opening new buffer
  local current = vim.fn.expand "%:p"
  local alt = vim.fn.expand "#:p"
  local cmd = opts.args:gsub("%%:p", current):gsub("%%", current):gsub("#", alt)
  vim.cmd "new"
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "hide"
  vim.bo.swapfile = false
  vim.fn.termopen(cmd, {
    on_stdout = function()
      vim.schedule(function()
        vim.cmd "normal! G"
      end)
    end,
  })
  vim.api.nvim_buf_set_keymap(0, "n", "q", ":q!<CR>", { noremap = true, silent = true })
end, { nargs = "+", complete = "shellcmd" })

-- Quick help: :Tldr find, :Tldr tar
vim.api.nvim_create_user_command("Tldr", function(opts)
  vim.cmd("R tldr " .. opts.args)
end, { nargs = 1 })

-- Bash keywords/builtins: :BashHelp for, :BashHelp while, :BashHelp if
vim.api.nvim_create_user_command("BashHelp", function(opts)
  vim.cmd("R bash -c 'help " .. opts.args .. "'")
end, { nargs = 1 })

-- Search bash help: :BashSearch do → finds for, while, until, select
vim.api.nvim_create_user_command("BashSearch", function(opts)
  vim.cmd("R bash -c 'help' 2>&1 | grep -i '" .. opts.args .. "'")
end, { nargs = 1 })

-- Shellcheck wiki: :SC SC2045 → opens wiki explanation
vim.api.nvim_create_user_command("SC", function(opts)
  local code = opts.args:upper():gsub("SC", "")
  local url = "https://www.shellcheck.net/wiki/SC" .. code
  local output = vim.fn.systemlist("curl -sL " .. url .. " | pandoc -f html -t markdown")
  vim.cmd "new"
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "wipe"
  vim.bo.swapfile = false
  vim.bo.filetype = "markdown"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, output)
  vim.api.nvim_buf_set_keymap(0, "n", "q", ":q!<CR>", { noremap = true, silent = true })
end, { nargs = 1 })

-- Quickfix/Trouble: Press K on shellcheck error to open wiki
local function shellcheck_wiki_lookup()
  local line = vim.fn.getline "."
  -- Match both [SC2045] and (SC2045) formats
  local code = line:match "[%[%(]SC(%d+)[%]%)]"
  if code then
    vim.cmd("SC " .. code)
  else
    vim.notify("No SC code found on this line", vim.log.levels.WARN)
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "qf", "trouble" },
  callback = function()
    vim.keymap.set("n", "K", shellcheck_wiki_lookup, { buffer = true, desc = "Open shellcheck wiki" })
  end,
})

-- Topic search: :Cheat substring (defaults to bash)
-- Or specify language: :Cheat python list comprehension
vim.api.nvim_create_user_command("Cheat", function(opts)
  local args = vim.split(opts.args, " ")
  local lang = "bash"
  local query_start = 1
  -- Check if first arg is a known language
  local langs =
    { python = 1, go = 1, rust = 1, js = 1, lua = 1, c = 1, cpp = 1, java = 1, ruby = 1, perl = 1, bash = 1, sh = 1 }
  if langs[args[1]] then
    lang = args[1]
    query_start = 2
  end
  local query = table.concat(args, "+", query_start)
  vim.cmd("R curl -s cht.sh/" .. lang .. "/" .. query)
end, { nargs = "+" })

-- Telescope pickers for help
vim.api.nvim_create_user_command("TldrPick", function()
  require("user_functions.telescope_help").tldr()
end, { desc = "Telescope tldr picker" })

vim.api.nvim_create_user_command("CheatPick", function()
  require("user_functions.telescope_help").cheat()
end, { desc = "Telescope cheat.sh picker" })

vim.api.nvim_create_user_command("BashBible", function()
  require("user_functions.telescope_help").bash_bible()
end, { desc = "Telescope pure-bash-bible picker" })

vim.api.nvim_create_user_command("TMarkn", function()
  vim.cmd [[execute "r !~/dev/dotfiles/scripts/__list_tasks_as_markdown.pl '+next'" ]]
end, {})

vim.api.nvim_create_user_command("T", function()
  vim.cmd ":sp term://zsh"
  vim.cmd "startinsert"
end, {})

vim.api.nvim_create_user_command("VT", function()
  vim.cmd ":vsp term://zsh"
  vim.cmd "startinsert"
end, {})

vim.api.nvim_create_user_command("PlantUmlOpen", function()
  -- local file_path = vim.fn.expand "%:p" -- unused
  local file_dir = vim.fn.expand "%:p:h"
  local file_name = vim.fn.expand "%:t:r"
  local svg_path = file_dir .. "/rendered/" .. file_name .. ".svg"

  -- Check if SVG exists
  if vim.fn.filereadable(svg_path) == 0 then
    -- Generate it first
    generate_plantuml()
    vim.fn.system { "sleep", "1" } -- Wait for generation
  end

  -- Open the SVG
  if sysname == "Darwin" then
    vim.fn.system { "open", svg_path }
  else
    vim.fn.system { "xdg-open", svg_path }
  end
end, { desc = "Open rendered PlantUML diagram" })

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

-- Terraform
vim.cmd [[silent! autocmd! filetypedetect BufRead,BufNewFile *.tf]]
vim.cmd [[autocmd BufRead,BufNewFile *.hcl set filetype=hcl]]
vim.api.nvim_create_autocmd({ "BufWritePre" }, {
  pattern = { "*.tf", "*.tfvars" },
  callback = function()
    vim.lsp.buf.format()
  end,
})

-- Systemd Services
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.service", "*.timer" },
  callback = function()
    vim.bo.filetype = "dosini"
  end,
})
