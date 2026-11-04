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
local terminalGroup = api.nvim_create_augroup("Terminal", { clear = true })
local presentermGroup = api.nvim_create_augroup("Presenterm", { clear = true })

-- Terminal OSC Sequences
-- OSC 7: Directory tracking (shell reports CWD changes)
api.nvim_create_autocmd("TermRequest", {
  group = terminalGroup,
  callback = function(ev)
    local val = string.gsub(ev.data.sequence, "\027]7;file://[^/]*", "")
    if val ~= ev.data.sequence then
      vim.bo[ev.buf].path = val
    end
  end,
  desc = "Handle OSC 7 directory change requests",
})

-- OSC 133: Prompt markers (]] and [[ jump between prompts)
local prompt_ns = api.nvim_create_namespace "terminal.prompt"
api.nvim_create_autocmd("TermRequest", {
  group = terminalGroup,
  callback = function(args)
    if string.match(args.data.sequence, "^\027]133;A") then
      local lnum = args.data.cursor[1]
      -- Get line length to position cursor at end (where you type)
      local line = api.nvim_buf_get_lines(args.buf, lnum - 1, lnum, false)[1] or ""
      api.nvim_buf_set_extmark(args.buf, prompt_ns, lnum - 1, #line, {
        sign_text = "➜",
        sign_hl_group = "SpecialChar",
      })
    end
  end,
  desc = "Handle OSC 133 prompt markers",
})

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
  vim.b.no_auto_close = true
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

vim.api.nvim_create_user_command("PumlRender", function()
  local file_dir = vim.fn.expand "%:p:h"
  local file_name = vim.fn.expand "%:t:r"
  local svg_path = file_dir .. "/rendered/" .. file_name .. ".svg"

  -- Generate SVG
  generate_plantuml()
  vim.fn.system { "sleep", "1" } -- Wait for generation

  -- Open the SVG
  if sysname == "Darwin" then
    vim.fn.system { "open", svg_path }
  else
    vim.fn.system { "xdg-open", svg_path }
  end
end, { desc = "Render to ./rendered/ and open SVG" })

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
    vim.hl.on_yank { higroup = "IncSearch", timeout = 250 }
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

-- Presenterm: normalize blank lines after slide separators on save.
-- presenterm decks accumulate blank lines after every "<!-- end_slide -->"
-- (the plugin's new_slide seeds three). Collapse each run to exactly one blank
-- line, except when the marker ends the file (then keep no trailing blank).
-- Detection is by filename for now: only presentation.md is touched.
local function presenterm_normalize_slide_gaps(bufnr)
  local marker = "<!-- end_slide -->"
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local out = {}
  local i, n = 1, #lines
  while i <= n do
    out[#out + 1] = lines[i]
    if vim.trim(lines[i]) == marker then
      local j = i + 1
      while j <= n and lines[j]:match "^%s*$" do
        j = j + 1
      end
      if j <= n then
        out[#out + 1] = "" -- content follows: keep exactly one blank line
      end
      i = j -- skip the original blank run (or stop at end of file)
    else
      i = i + 1
    end
  end
  if not vim.deep_equal(out, lines) then
    local view = vim.fn.winsaveview()
    api.nvim_buf_set_lines(bufnr, 0, -1, false, out)
    pcall(vim.fn.winrestview, view)
  end
end

vim.api.nvim_create_autocmd("BufWritePre", {
  group = presentermGroup,
  pattern = "presentation.md",
  callback = function(ev)
    presenterm_normalize_slide_gaps(ev.buf)
  end,
  desc = "Collapse blank lines after presenterm end_slide markers",
})

-- Gordon handoff files: each editable buffer holds one handoff. Saves send
-- Piotr's reply to Gordon (notes it on the task, DMs triage).
local handoffsGroup = api.nvim_create_augroup("GordonHandoffs", { clear = true })
local handoffs_legacy = vim.env.HOME .. "/.local/state/gordon/handoffs.md"
local handoffs_dir = vim.env.HOME .. "/.local/state/gordon/handoffs"
local handoffs_pattern = handoffs_dir .. "/**.md"
local handoffs_index = handoffs_dir .. "/index.md"
local handoffs_patterns = { handoffs_legacy, handoffs_pattern }
local handoffs_saves = {}
local handoffs_acks = {}
vim.api.nvim_create_autocmd("BufWritePost", {
  group = handoffsGroup,
  pattern = handoffs_patterns,
  callback = function(ev)
    if ev.file == handoffs_index then
      return
    end
    local script = vim.env.HOME .. "/.claude/scripts/__handoffs_file.py"
    local command = ev.file == handoffs_legacy and { script, "save" } or { script, "save", ev.file }
    handoffs_saves[ev.buf] = vim.system(command, { text = true, detach = true }, function(res)
      vim.schedule(function()
        if res.code == 0 then
          local sent = vim.trim(res.stdout or "")
          if sent ~= "" then
            vim.notify("sent to Gordon: " .. sent, vim.log.levels.INFO)
          end
        else
          vim.notify("handoffs save failed: " .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
        end
      end)
    end)
  end,
  desc = "Deliver handoff replies to Gordon on save",
})

local function handoff_uuid(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  for row = api.nvim_win_get_cursor(0)[1], 1, -1 do
    if lines[row]:match "^## " then
      local uuid = (lines[row + 1] or ""):match "^<!%-%- handoff: ([0-9a-f%-]+) %-%->$"
      if uuid then
        local a, b, c, d, e = uuid:match "^(%x+)%-(%x+)%-(%x+)%-(%x+)%-(%x+)$"
        if a and #a == 8 and #b == 4 and #c == 4 and #d == 4 and #e == 12 then
          return uuid
        end
      end
      return nil
    end
  end
end

local function handoffs_write(buf)
  if vim.bo[buf].modified then
    local ok, err = pcall(vim.cmd, "write")
    if not ok then
      vim.notify(tostring(err), vim.log.levels.ERROR)
      return false
    end
  end
  local job = handoffs_saves[buf]
  if job and job:wait(60000).code ~= 0 then
    vim.notify("Reply delivery failed; save again to retry.", vim.log.levels.ERROR)
    return false
  end
  return true
end

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = handoffsGroup,
  pattern = handoffs_patterns,
  callback = function(ev)
    if ev.file == handoffs_index or ev.file == handoffs_legacy then
      vim.bo[ev.buf].filetype = "markdown"
      vim.bo[ev.buf].readonly = true
      return
    end
    vim.bo[ev.buf].filetype = "markdown"
    vim.wo.wrap = true
    vim.wo.linebreak = true
    vim.wo.breakindent = true
    vim.wo.winbar = " a: ack/reply  Enter: unfurl  s: spawn  d: close (confirm)  [[/]]: handoff  q/Esc: close "
    local function navigate(direction)
      local script = vim.env.HOME .. "/.claude/scripts/__handoffs_file.py"
      local step = direction > 0 and "next" or "prev"
      local path = vim.fn.system { script, "neighbor", ev.file, step }
      if vim.v.shell_error ~= 0 or vim.trim(path) == "" then
        vim.notify("No more handoffs", vim.log.levels.INFO)
        return
      end
      vim.cmd.edit(vim.fn.fnameescape(vim.trim(path)))
      local lines = api.nvim_buf_get_lines(0, 0, -1, false)
      for row, line in ipairs(lines) do
        if line:match "^>" then
          api.nvim_win_set_cursor(0, { row, 0 })
          return
        end
      end
    end
    vim.defer_fn(function()
      if not api.nvim_buf_is_valid(ev.buf) then
        return
      end
      vim.keymap.set("n", "]]", function()
        navigate(1)
      end, { buffer = ev.buf, silent = true, desc = "Next handoff" })
      vim.keymap.set("n", "[[", function()
        navigate(-1)
      end, { buffer = ev.buf, silent = true, desc = "Previous handoff" })
    end, 200)
    local function close()
      if vim.bo[ev.buf].modified then
        local choice = vim.fn.confirm("Save handoff replies before closing?", "&Save\n&Cancel\n&Discard", 2)
        if choice == 1 then
          local ok, err = pcall(vim.cmd, "write")
          if not ok then
            vim.notify(tostring(err), vim.log.levels.ERROR)
            return
          end
        elseif choice ~= 3 then
          return
        end
      end
      vim.cmd "quit!"
    end
    local function act(action)
      local uuid = handoff_uuid(ev.buf)
      if not uuid then
        vim.notify("Place the cursor on a handoff with a UUID marker.", vim.log.levels.WARN)
        return
      end
      if action == "done" then
        local heading = ""
        for row = api.nvim_win_get_cursor(0)[1], 1, -1 do
          local line = api.nvim_buf_get_lines(ev.buf, row - 1, row, false)[1]
          if line:match "^## " then
            heading = line:sub(4)
            break
          end
        end
        if vim.fn.confirm("Close " .. heading .. "?", "&Yes\n&No", 2) ~= 1 then
          return
        end
      end
      if not handoffs_write(ev.buf) then
        return
      end
      local script = vim.env.HOME .. "/dev/dotfiles/scripts/__task_brief.sh"
      local result = vim.fn.system { script, "--action", action, uuid }
      if vim.v.shell_error ~= 0 then
        vim.notify(vim.trim(result), vim.log.levels.ERROR)
        return
      end
      vim.cmd "quit"
    end
    local function ack()
      if handoffs_acks[ev.buf] then
        return
      end
      local uuid = handoff_uuid(ev.buf)
      if not uuid then
        vim.notify("Place the cursor on a handoff with a UUID marker.", vim.log.levels.WARN)
        return
      end
      if vim.bo[ev.buf].modified then
        vim.notify("Save handoff edits before acking.", vim.log.levels.WARN)
        return
      end
      handoffs_acks[ev.buf] = true
      vim.ui.input({ prompt = "Comment (optional): ", default = "" }, function(comment)
        if comment == nil or not api.nvim_buf_is_valid(ev.buf) then
          handoffs_acks[ev.buf] = nil
          return
        end
        local script = vim.env.HOME .. "/.claude/scripts/__handoffs_file.py"
        vim.system({ script, "ack", uuid, comment }, { text = true, detach = true }, function(result)
          vim.schedule(function()
            handoffs_acks[ev.buf] = nil
            if result.code ~= 0 then
              vim.notify("Handoff ack failed: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
              return
            end
            local output = vim.trim(result.stdout or "")
            local json = output:match "([^\n]+)$" or output
            local ok, response = pcall(vim.json.decode, json)
            if not ok or type(response) ~= "table" then
              vim.notify("Handoff ack returned an invalid response.", vim.log.levels.ERROR)
              return
            end
            if response.closed then
              if api.nvim_buf_is_valid(ev.buf) and api.nvim_buf_get_option(ev.buf, "modified") then
                vim.notify("Handoff was acked, but this buffer has unsaved edits.", vim.log.levels.WARN)
                return
              end
              if api.nvim_buf_is_valid(ev.buf) and api.nvim_buf_delete then
                pcall(api.nvim_buf_delete, ev.buf, { force = true })
              end
            else
              vim.notify("Reply sent. This task is not tagged +ack, so it remains open.", vim.log.levels.INFO)
            end
          end)
        end)
      end)
    end
    for key, action in pairs { ["<CR>"] = "enter", s = "spawn", d = "done" } do
      vim.keymap.set("n", key, function()
        act(action)
      end, { buffer = ev.buf, silent = true, desc = "Handoff: " .. action })
    end
    vim.keymap.set("n", "a", ack, { buffer = ev.buf, silent = true, desc = "Ack or reply to handoff" })
    for _, key in ipairs { "q", "<Esc>" } do
      vim.keymap.set("n", key, close, { buffer = ev.buf, silent = true, desc = "Close handoffs" })
    end
  end,
  desc = "Edit handoffs with actions for the item under the cursor",
})

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = handoffsGroup,
  pattern = handoffs_index,
  callback = function(ev)
    vim.bo[ev.buf].filetype = "markdown"
    vim.bo[ev.buf].modifiable = false
    vim.bo[ev.buf].readonly = true
    vim.wo.wrap = true
    vim.wo.linebreak = true
    vim.wo.winbar = " Enter: open handoff  [[/]]: handoff  q/Esc: close "
    local function neighbor(direction)
      local script = vim.env.HOME .. "/.claude/scripts/__handoffs_file.py"
      local step = direction > 0 and "next" or "prev"
      local path = vim.fn.system { script, "neighbor", ev.file, step }
      if vim.v.shell_error ~= 0 or vim.trim(path) == "" then
        vim.notify("No more handoffs", vim.log.levels.INFO)
        return
      end
      vim.cmd.edit(vim.fn.fnameescape(vim.trim(path)))
    end
    vim.keymap.set("n", "<CR>", function()
      local line = api.nvim_get_current_line()
      local target = line:match "%]%(([^)]+)%)"
      if not target then
        vim.notify("Place the cursor on a handoff link.", vim.log.levels.WARN)
        return
      end
      target = target:gsub("^<", ""):gsub(">$", "")
      local path = vim.fs.normalize(vim.fn.fnamemodify(ev.file, ":h") .. "/" .. target)
      vim.cmd.edit(vim.fn.fnameescape(path))
    end, { buffer = ev.buf, silent = true, desc = "Open handoff" })
    vim.keymap.set("n", "]]", function()
      neighbor(1)
    end, { buffer = ev.buf, silent = true, desc = "Next handoff" })
    vim.keymap.set("n", "[[", function()
      neighbor(-1)
    end, { buffer = ev.buf, silent = true, desc = "Previous handoff" })
  end,
  desc = "Browse handoff index without editing it",
})
