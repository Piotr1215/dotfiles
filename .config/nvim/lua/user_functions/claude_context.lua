-- Claude Context Assistant - Native Neovim Integration
-- Provides context-aware Claude assistance through git diffs

local M = {}

-- Configuration
local config = {
  claude_path = "/home/decoder/.npm-global/bin/claude",
  diff_context_lines = 10,
  enabled = true,
  -- Simple filtering - git already handles most of this via .gitignore
  filter = {
    ignore_whitespace_only = true, -- Skip pure formatting changes
    ignore_comment_only = false, -- Keep comments - they show intent
    min_change_lines = 0, -- Send all real changes
    batch_delay_ms = 1500, -- 1.5s delay to group related saves
  },
  -- Track files Claude has worked on
  relevant_files = {},
  pending_updates = {},
  -- Standard FYI message appended to all context updates
  fyi_suffix = "\nThis is FYI only - DO NOT take any action. Wait for explicit instructions.\n",
  -- Experimental LSP integration
  lsp_enabled = true, -- Set to true to enable LSP semantic context
}

-- State
local state = {
  claude_buf = nil,
  claude_job_id = nil,
  claude_win = nil,
  session_start = os.time(),
  last_status_update = 0,
  added_directories = {}, -- Track which directories we've added to Claude
  lsp_diagnostics_cache = {}, -- Cache LSP diagnostics per buffer
}

-- Helper: Check if diff is significant
local function is_significant_diff(diff)
  if not diff or diff == "" then
    return false
  end

  local lines = vim.split(diff, "\n")
  local added_lines = 0
  local removed_lines = 0
  local has_non_whitespace = false
  local has_non_comment = false

  for _, line in ipairs(lines) do
    if line:match "^%+[^%+]" then
      added_lines = added_lines + 1
      -- Check if it's more than just whitespace
      if line:match "%S" then
        has_non_whitespace = true
      end
      -- Check if it's not just a comment (basic check for common languages)
      if
        not line:match "^%+%s*//"
        and not line:match "^%+%s*#"
        and not line:match "^%+%s*%-%-"
        and not line:match "^%+%s*%*"
      then
        has_non_comment = true
      end
    elseif line:match "^%-[^%-]" then
      removed_lines = removed_lines + 1
      if line:match "%S" then
        has_non_whitespace = true
      end
      if
        not line:match "^%-%s*//"
        and not line:match "^%-%s*#"
        and not line:match "^%-%s*%-%-"
        and not line:match "^%-%s*%*"
      then
        has_non_comment = true
      end
    end
  end

  local total_changes = added_lines + removed_lines

  -- Apply filters
  if total_changes < config.filter.min_change_lines then
    return false
  end

  if config.filter.ignore_whitespace_only and not has_non_whitespace then
    return false
  end

  if config.filter.ignore_comment_only and not has_non_comment then
    return false
  end

  return true
end

-- Helper: Find Claude terminal buffer
local function find_claude_terminal()
  -- First check if buffer is in a window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].is_claude_assistant then
      return buf, win, vim.b[buf].terminal_job_id
    end
  end

  -- If not in a window, search all buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].is_claude_assistant then
      return buf, nil, vim.b[buf].terminal_job_id
    end
  end

  return nil, nil, nil
end

-- Helper: Update status indicator for lualine
local function update_indicator()
  local buf = find_claude_terminal()
  if not buf then
    vim.g.claude_context_indicator = "" -- Claude not running
  elseif config.enabled then
    vim.g.claude_context_indicator = "[C]" -- Claude active, diffs on
  else
    vim.g.claude_context_indicator = "[C-off]" -- Claude active, diffs off
  end
end

-- Helper: Format context update message
local function format_context_update(filepath, diff)
  local timestamp = os.date "%H:%M:%S"
  local message = string.format("\n=== FYI: Context Update [%s] ===\nFile saved: %s\n", timestamp, filepath)

  -- Get statistics about other modified files (don't list them all)
  local git_status = vim.fn.system "git status --porcelain 2>/dev/null"
  if git_status ~= "" then
    local current_file = vim.fn.fnamemodify(filepath, ":.") -- Make filepath relative for comparison
    local staged_count = 0
    local modified_count = 0
    local untracked_count = 0

    for line in git_status:gmatch "[^\n]+" do
      local status_code = line:sub(1, 2)
      local filename = line:match "^.. (.+)$"

      if filename and filename ~= current_file then
        if status_code:match "^[MADRC]" then
          staged_count = staged_count + 1
        end
        if status_code:match ".[MD]" then
          modified_count = modified_count + 1
        end
        if status_code == "??" then
          untracked_count = untracked_count + 1
        end
      end
    end

    local other_changes = {}
    if staged_count > 0 then
      table.insert(other_changes, staged_count .. " staged")
    end
    if modified_count > 0 then
      table.insert(other_changes, modified_count .. " modified")
    end
    if untracked_count > 0 then
      table.insert(other_changes, untracked_count .. " untracked")
    end

    if #other_changes > 0 then
      message = message .. "Other files: " .. table.concat(other_changes, ", ") .. "\n"
    end
  end

  if diff and diff ~= "" then
    -- Clean up the diff output
    local lines = vim.split(diff, "\n")
    local clean_diff = {}
    for _, line in ipairs(lines) do
      -- Skip binary file messages and empty lines at the end
      if not line:match "^Binary files" and (line ~= "" or #clean_diff > 0) then
        table.insert(clean_diff, line)
      end
    end

    if #clean_diff > 0 then
      message = message .. "Changes:\n```diff\n" .. table.concat(clean_diff, "\n") .. "\n```\n"
    else
      message = message .. "File saved (no git changes detected)\n"
    end
  else
    message = message .. "File saved (not in git repository)\n"
  end

  message = message .. config.fyi_suffix
  message = message .. "=== End Context Update ===\n\n"
  return message
end

-- Core: Send message to Claude terminal
local function send_to_claude(message)
  local buf, win, job_id = find_claude_terminal()

  if not buf or not job_id then
    vim.notify("Claude assistant not running. Use :ClaudeStart to begin.", vim.log.levels.WARN)
    return false
  end

  -- Send message first
  vim.fn.chansend(job_id, message)

  -- Wait for message to be processed, then send ACTUAL Enter key (not newline)
  vim.defer_fn(function()
    -- Send Control-M (carriage return) which is the actual Enter key
    -- NOT \n which Claude interprets as a newline in the text!
    vim.fn.chansend(job_id, string.char(13)) -- ASCII 13 = CR = Enter key

    -- Jump to end to maintain autoscroll for next output
    if win then
      -- Use feedkeys instead of norm to avoid terminal mode conflict
      vim.api.nvim_win_call(win, function()
        if vim.api.nvim_get_mode().mode ~= "t" then
          vim.cmd "norm G"
        end
      end)
    end
  end, 500) -- Half second delay

  return true
end

-- Helper: Get git root directory
local function get_git_root()
  local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
  if vim.v.shell_error == 0 and git_root ~= "" then
    return git_root
  end
  return nil
end

-- Main: Start Claude assistant
function M.start_claude()
  -- Check if already running
  local existing_buf = find_claude_terminal()
  if existing_buf then
    vim.notify("Claude assistant already running", vim.log.levels.INFO)
    return
  end

  -- Clear tracked directories for fresh session
  state.added_directories = {}

  -- Get directory for Claude - prefer git root, fallback to cwd
  local git_root = get_git_root()
  local cwd = git_root or vim.fn.getcwd()

  -- Track initial directory as already added
  state.added_directories[cwd] = true

  -- Build claude command with directory permissions and auto-accept edits
  -- --add-dir grants access to the directory
  -- --permission-mode acceptEdits automatically accepts all file edits without prompting
  local claude_cmd = config.claude_path .. " --add-dir " .. vim.fn.shellescape(cwd) .. " --permission-mode acceptEdits"

  -- Open Claude in a vertical split on the left (40% width for Claude, 60% for editor)
  -- The $NVIM environment variable is automatically set by Neovim terminal
  -- Use the cwd option to start the terminal in the git root directory
  local width = math.floor(vim.o.columns * 0.4)
  vim.cmd("leftabove " .. width .. "vsplit term://" .. cwd .. "//" .. claude_cmd)

  -- Mark this terminal as the Claude assistant
  local buf = vim.api.nvim_get_current_buf()
  vim.b[buf].is_claude_assistant = true

  -- Store state
  state.claude_buf = buf
  state.claude_win = vim.api.nvim_get_current_win()
  state.claude_job_id = vim.b[buf].terminal_job_id

  -- Start in insert mode for the terminal
  vim.cmd "startinsert"

  -- Set autocmd to always enter insert mode when entering this terminal
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      vim.cmd "startinsert"
    end,
  })

  -- Add terminal-specific mappings with higher priority to override global mappings
  -- Use vim.keymap.set with buffer option for better priority handling
  vim.keymap.set("t", "<C-l>", "<C-\\><C-n><C-w>l", {
    buffer = buf,
    noremap = true,
    silent = true,
    desc = "Switch to right window from Claude terminal",
  })

  vim.keymap.set("t", "<C-h>", "<C-\\><C-n><C-w>h", {
    buffer = buf,
    noremap = true,
    silent = true,
    desc = "Switch to left window from Claude terminal",
  })

  -- Also override the tmux navigation for this specific buffer
  vim.keymap.set("t", "<C-j>", "<C-\\><C-n><C-w>j", {
    buffer = buf,
    noremap = true,
    silent = true,
    desc = "Switch to window below from Claude terminal",
  })

  vim.keymap.set("t", "<C-k>", "<C-\\><C-n><C-w>k", {
    buffer = buf,
    noremap = true,
    silent = true,
    desc = "Switch to window above from Claude terminal",
  })

  -- Jump to last line to enable terminal's native autoscroll
  vim.cmd "norm G"

  -- Return to previous window but keep terminal in insert mode
  vim.cmd "stopinsert" -- Stop insert mode for current window
  vim.cmd "wincmd p"

  -- Update indicator
  update_indicator()
end

-- Toggle Claude window
function M.toggle_claude()
  local buf, win = find_claude_terminal()
  if win then
    -- Window is visible, hide it and pause git diff sending
    vim.api.nvim_win_close(win, false)
    config.enabled = false
  elseif buf then
    -- Buffer exists but no window, create one and resume git diff sending
    local width = math.floor(vim.o.columns * 0.4)
    vim.cmd("leftabove " .. width .. "vsplit")
    vim.api.nvim_set_current_buf(buf)
    vim.cmd "wincmd p"
    config.enabled = true
  else
    -- No Claude session exists, start one
    M.start_claude()
  end
  update_indicator() -- Update after toggle
end

-- Stop Claude completely
function M.stop_claude()
  local buf, win, job_id = find_claude_terminal()

  if not buf then
    vim.notify("Claude is not running", vim.log.levels.INFO)
    return
  end

  -- Close window if visible
  if win then
    vim.api.nvim_win_close(win, false)
  end

  -- Stop the job if running
  if job_id then
    vim.fn.jobstop(job_id)
  end

  -- Delete the buffer
  vim.api.nvim_buf_delete(buf, { force = true })

  -- Reset state
  state.claude_buf = nil
  state.claude_job_id = nil
  state.claude_win = nil
  state.added_directories = {}
  config.enabled = true

  -- Update indicator
  update_indicator()

  vim.notify("Claude session stopped", vim.log.levels.INFO)
end

-- Helper: Get LSP semantic context for current position
local function get_lsp_context(bufnr)
  if not config.lsp_enabled then
    return nil
  end

  local context = {
    diagnostics = {},
    hover_info = nil,
    references_count = 0,
    definition = nil,
  }

  -- Get diagnostics for current buffer
  local diagnostics = vim.diagnostic.get(bufnr)
  -- Debug: Log diagnostic count
  if #diagnostics > 0 then
    vim.notify(string.format("Found %d diagnostics in buffer", #diagnostics), vim.log.levels.DEBUG)
  end

  for _, diag in ipairs(diagnostics) do
    -- Get severity name
    local severity_name = "UNKNOWN"
    if diag.severity == vim.diagnostic.severity.ERROR then
      severity_name = "ERROR"
    elseif diag.severity == vim.diagnostic.severity.WARN then
      severity_name = "WARN"
    elseif diag.severity == vim.diagnostic.severity.INFO then
      severity_name = "INFO"
    elseif diag.severity == vim.diagnostic.severity.HINT then
      severity_name = "HINT"
    end

    table.insert(context.diagnostics, {
      line = diag.lnum + 1,
      severity = severity_name,
      message = diag.message,
      source = diag.source or "unknown",
    })
  end

  -- Get current cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local params = vim.lsp.util.make_position_params()

  -- Try to get hover information (type info, docs)
  local hover_result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", params, 1000)
  if hover_result and next(hover_result) then
    for _, result in pairs(hover_result) do
      if result.result and result.result.contents then
        context.hover_info = vim.lsp.util.convert_input_to_markdown_lines(result.result.contents)
      end
    end
  end

  -- Get reference count
  local ref_result = vim.lsp.buf_request_sync(bufnr, "textDocument/references", params, 1000)
  if ref_result and next(ref_result) then
    for _, result in pairs(ref_result) do
      if result.result then
        context.references_count = #result.result
      end
    end
  end

  return context
end

-- Helper: Format LSP context for Claude
local function format_lsp_context(lsp_context, filepath)
  if not lsp_context then
    return ""
  end

  local message = "\n=== LSP Semantic Context ===\n"

  -- Add diagnostics if any
  if #lsp_context.diagnostics > 0 then
    message = message .. "\n**Diagnostics Found:**\n"
    for _, diag in ipairs(lsp_context.diagnostics) do
      message = message
        .. string.format("  • Line %d [%s]: %s (from %s)\n", diag.line, diag.severity, diag.message, diag.source)
    end
  end

  -- Add hover info if available
  if lsp_context.hover_info then
    message = message .. "\n**Type/Documentation:**\n"
    message = message .. table.concat(lsp_context.hover_info, "\n") .. "\n"
  end

  -- Add references count
  if lsp_context.references_count > 0 then
    message = message
      .. string.format(
        "\n**References:** This code is referenced in %d other location(s)\n",
        lsp_context.references_count
      )
  end

  return message
end

-- Batch timer for collecting multiple updates
local batch_timer = nil

-- Send batched updates
local function send_batched_updates()
  if not next(config.pending_updates) then
    return
  end

  local timestamp = os.date "%H:%M:%S"
  local message = string.format("\n=== FYI: Batched Context Update [%s] ===\nFiles saved:\n", timestamp)

  -- List files being sent with diffs
  for filepath, _ in pairs(config.pending_updates) do
    message = message .. string.format("• %s (diff included)\n", filepath)
  end

  -- Get other modified files and show statistics only
  local git_status = vim.fn.system "git status --porcelain 2>/dev/null"
  if git_status ~= "" then
    local other_files = {}
    local staged_count = 0
    local modified_count = 0

    for line in git_status:gmatch "[^\n]+" do
      local status_code = line:sub(1, 2)
      local filename = line:match "^.. (.+)$"

      if filename and not config.pending_updates[filename] then
        if status_code:match "^[MADRC]" then
          staged_count = staged_count + 1
        end
        if status_code:match ".[MD]" then
          modified_count = modified_count + 1
        end
        if #other_files < 5 then -- Show first 5 files only
          table.insert(other_files, filename)
        end
      end
    end

    if staged_count > 0 or modified_count > 0 then
      message = message .. "\nOther changes in workspace:\n"
      if staged_count > 0 then
        message = message .. string.format("  • %d file(s) staged\n", staged_count)
      end
      if modified_count > 0 then
        message = message .. string.format("  • %d file(s) modified\n", modified_count)
      end
      if #other_files > 0 then
        message = message .. "  First few: " .. table.concat(other_files, ", ")
        if staged_count + modified_count > 5 then
          message = message .. ", ..."
        end
        message = message .. "\n"
      end
    end
  end

  message = message .. "\nChanges:\n"

  -- Only include diffs for the files that were actually saved
  for filepath, update_data in pairs(config.pending_updates) do
    local diff = update_data.diff or update_data -- Support both old and new format
    local lsp_context = type(update_data) == "table" and update_data.lsp_context or nil

    message = message .. string.format("\n--- %s ---\n```diff\n%s\n```\n", filepath, diff)

    -- Add LSP context if available
    if lsp_context then
      local lsp_msg = format_lsp_context(lsp_context, filepath)
      if lsp_msg ~= "" then
        message = message .. lsp_msg
      end
    end
  end

  message = message .. config.fyi_suffix
  message = message .. "=== End Context Update ===\n\n"

  send_to_claude(message)
  config.pending_updates = {}
end

-- Helper function to continue sending context after LSP is ready
local function send_context_with_lsp(filepath, relative_path, diff, lsp_context, force)
  -- If batching is enabled, add to pending updates
  if config.filter.batch_delay_ms > 0 and not force then
    config.pending_updates[relative_path] = { diff = diff, lsp_context = lsp_context }

    -- Cancel existing timer
    if batch_timer then
      batch_timer:stop()
    end

    -- Start new timer
    batch_timer = vim.loop.new_timer()
    batch_timer:start(
      config.filter.batch_delay_ms,
      0,
      vim.schedule_wrap(function()
        send_batched_updates()
        batch_timer = nil
      end)
    )
  else
    -- Send immediately
    local message = format_context_update(relative_path, diff)

    -- Add LSP context if available
    if lsp_context then
      local lsp_msg = format_lsp_context(lsp_context, filepath)
      if lsp_msg ~= "" then
        message = message:gsub(config.fyi_suffix, lsp_msg .. "\n" .. config.fyi_suffix)
      end
    end

    send_to_claude(message)
  end
end

-- Send current file context (with smart filtering)
function M.send_context(force)
  local filepath = vim.fn.expand "%:p"
  local relative_path = vim.fn.fnamemodify(filepath, ":.")
  local bufnr = vim.api.nvim_get_current_buf()

  -- Get UNSTAGED changes only (not showing already staged work)
  -- This way, once you stage completed work, Claude only sees new changes
  local diff_cmd = string.format("git diff --unified=%d -- %s", config.diff_context_lines, vim.fn.shellescape(filepath))
  local diff = vim.fn.system(diff_cmd)

  -- Check if diff is significant
  if not force and not is_significant_diff(diff) then
    return
  end

  -- Get LSP context if enabled and available
  local lsp_context = nil
  if config.lsp_enabled then
    -- Add a small delay to ensure LSP diagnostics are ready
    vim.defer_fn(function()
      lsp_context = get_lsp_context(bufnr)
      -- Continue with the rest of the function
      send_context_with_lsp(filepath, relative_path, diff, lsp_context, force)
    end, 200) -- 200ms delay for LSP to process
    return
  end

  -- If LSP is disabled, continue without delay
  send_context_with_lsp(filepath, relative_path, diff, nil, force)
end

-- Send arbitrary message
function M.send_message(message)
  if message and message ~= "" then
    send_to_claude("\n>>> " .. message .. "\n\n")
  end
end

-- Send comprehensive git status with all diffs
function M.send_git_status()
  local timestamp = os.date "%H:%M:%S"
  local message = string.format("\n=== COMPREHENSIVE GIT OVERVIEW [%s] ===\n", timestamp)

  -- Current branch and upstream
  local branch = vim.fn.system("git branch --show-current 2>/dev/null"):gsub("\n", "")
  local upstream = vim.fn.system("git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null"):gsub("\n", "")
  message = message .. "Branch: " .. branch
  if upstream ~= "" then
    message = message .. " → " .. upstream
  end
  message = message .. "\n"

  -- Behind/ahead of upstream
  local rev_list = vim.fn.system("git rev-list --left-right --count HEAD...@{u} 2>/dev/null"):gsub("\n", "")
  if rev_list ~= "" then
    local ahead, behind = rev_list:match "(%d+)%s+(%d+)"
    if ahead and behind then
      message = message .. string.format("↑ %s ahead, ↓ %s behind upstream\n", ahead, behind)
    end
  end

  -- File status summary
  local status = vim.fn.system "git status --porcelain 2>/dev/null"
  local staged_files = {}
  local unstaged_files = {}
  local untracked_files = {}

  for line in status:gmatch "[^\n]+" do
    local status_code = line:sub(1, 2)
    local filename = line:sub(4)

    if status_code:match "^[MADRC]" then
      table.insert(staged_files, filename)
    end
    if status_code:match ".[MD]" then
      table.insert(unstaged_files, filename)
    end
    if status_code == "??" then
      table.insert(untracked_files, filename)
    end
  end

  message = message .. "\nFILE STATUS:\n"
  if #staged_files > 0 then
    message = message .. "Staged (" .. #staged_files .. "):\n"
    for _, file in ipairs(staged_files) do
      message = message .. "  + " .. file .. "\n"
    end
  end

  if #unstaged_files > 0 then
    message = message .. "Unstaged (" .. #unstaged_files .. "):\n"
    for _, file in ipairs(unstaged_files) do
      message = message .. "  M " .. file .. "\n"
    end
  end

  if #untracked_files > 0 then
    message = message .. "Untracked (" .. #untracked_files .. "):\n"
    for _, file in ipairs(untracked_files) do
      message = message .. "  ? " .. file .. "\n"
    end
  end

  -- Staged changes (what will be committed)
  local staged_diff = vim.fn.system "git diff --cached --stat 2>/dev/null"
  if staged_diff ~= "" then
    message = message .. "\nSTAGED CHANGES (will be committed):\n```\n" .. staged_diff .. "```\n"

    -- Show actual staged diff (limited)
    local staged_diff_full = vim.fn.system "git diff --cached --unified=3 2>/dev/null"
    local lines = vim.split(staged_diff_full, "\n")
    if #lines > 50 then
      -- Truncate to first 50 lines
      local truncated = table.concat(vim.list_slice(lines, 1, 50), "\n")
      message = message .. "```diff\n" .. truncated .. "\n... (truncated, " .. (#lines - 50) .. " more lines)\n```\n"
    elseif #lines > 1 then
      message = message .. "```diff\n" .. staged_diff_full .. "```\n"
    end
  end

  -- Unstaged changes (working directory)
  local unstaged_diff = vim.fn.system "git diff --stat 2>/dev/null"
  if unstaged_diff ~= "" then
    message = message .. "\nUNSTAGED CHANGES (working directory):\n```\n" .. unstaged_diff .. "```\n"

    -- Show actual unstaged diff (limited)
    local unstaged_diff_full = vim.fn.system "git diff --unified=3 2>/dev/null"
    local lines = vim.split(unstaged_diff_full, "\n")
    if #lines > 50 then
      -- Truncate to first 50 lines
      local truncated = table.concat(vim.list_slice(lines, 1, 50), "\n")
      message = message .. "```diff\n" .. truncated .. "\n... (truncated, " .. (#lines - 50) .. " more lines)\n```\n"
    elseif #lines > 1 then
      message = message .. "```diff\n" .. unstaged_diff_full .. "```\n"
    end
  end

  -- Recent commits
  local commits = vim.fn.system "git log --oneline -10 2>/dev/null"
  if commits ~= "" then
    message = message .. "\nRECENT COMMITS:\n```\n" .. commits .. "```\n"
  end

  -- Stash status
  local stash = vim.fn.system "git stash list 2>/dev/null"
  if stash ~= "" then
    local stash_count = select(2, stash:gsub("\n", "\n"))
    message = message .. "\nSTASHES: " .. stash_count .. " stashed changes\n"
  end

  message = message .. config.fyi_suffix
  message = message .. "=== End Overview ===\n\n"

  send_to_claude(message)
end

-- Send untracked/unstaged files for Claude to read
function M.send_unstaged_files()
  local timestamp = os.date "%H:%M:%S"
  local git_status = vim.fn.system "git status --porcelain 2>/dev/null"

  if git_status == "" then
    vim.notify("No changes in working directory", vim.log.levels.INFO)
    return
  end

  local untracked_files = {}
  local modified_files = {}

  for line in git_status:gmatch "[^\n]+" do
    local status_code = line:sub(1, 2)
    local filename = line:sub(4) -- Skip status codes and space

    if status_code == "??" then
      table.insert(untracked_files, filename)
    elseif status_code:match "[MA ]M" or status_code:match "M[MD ]" then
      -- Modified in working tree (unstaged)
      table.insert(modified_files, filename)
    end
  end

  if #untracked_files == 0 and #modified_files == 0 then
    vim.notify("No untracked or modified unstaged files", vim.log.levels.INFO)
    return
  end

  local message = string.format("\n=== File Reading Request [%s] ===\n", timestamp)

  if #untracked_files > 0 then
    message = message .. "Please read these NEW untracked files:\n"
    for _, file in ipairs(untracked_files) do
      message = message .. "• " .. file .. "\n"
    end
  end

  if #modified_files > 0 then
    if #untracked_files > 0 then
      message = message .. "\n"
    end
    message = message .. "These tracked files have unstaged changes (use git diff to see changes):\n"
    for _, file in ipairs(modified_files) do
      message = message .. "• " .. file .. "\n"
    end
  end

  message = message .. "\nYou can read these files with your tools if I ask you to.\n"
  message = message .. config.fyi_suffix
  message = message .. "=== End Request ===\n\n"

  send_to_claude(message)
end

-- Setup periodic status updates
local status_timer = nil
function M.start_periodic_updates(interval_minutes)
  if status_timer then
    status_timer:stop()
  end

  local interval_ms = (interval_minutes or 10) * 60 * 1000
  status_timer = vim.loop.new_timer()

  status_timer:start(
    interval_ms,
    interval_ms,
    vim.schedule_wrap(function()
      local buf = find_claude_terminal()
      if buf then
        M.send_git_status()
      end
    end)
  )
end

function M.stop_periodic_updates()
  if status_timer then
    status_timer:stop()
    status_timer = nil
  end
end

-- Enable/disable git diff sending on file save
function M.toggle_git_diff_send()
  config.enabled = not config.enabled
  update_indicator() -- Update lualine indicator
end

-- Send file information about current buffer
function M.send_file_info()
  local filepath = vim.fn.expand "%:p"
  local filename = vim.fn.expand "%:t"
  local relative_path = vim.fn.fnamemodify(filepath, ":.")

  -- Skip certain files
  if filepath:match "%.git/" or filepath:match "node_modules/" or filepath:match "%.log$" or filename == "" then
    vim.notify("Cannot send info for this file type", vim.log.levels.WARN)
    return
  end

  local timestamp = os.date "%H:%M:%S"
  local message = string.format("\n=== FYI: File Context [%s] ===\n", timestamp)

  message = message .. "File: " .. relative_path .. "\n"

  -- Get file info
  local file_stat = vim.loop.fs_stat(filepath)
  if file_stat then
    local size = file_stat.size
    local size_str = size < 1024 and size .. "B"
      or size < 1024 * 1024 and string.format("%.1fKB", size / 1024)
      or string.format("%.1fMB", size / (1024 * 1024))
    message = message .. "Size: " .. size_str .. "\n"

    -- File type
    local filetype = vim.bo.filetype
    if filetype ~= "" then
      message = message .. "Type: " .. filetype .. "\n"
    end
  end

  -- Get git info if in git repo
  local git_root = get_git_root()
  if git_root then
    -- Last commit info for this file
    local last_commit = vim.fn
      .system(string.format("git log -1 --pretty='%%h %%s (%%ar by %%an)' -- %s 2>/dev/null", vim.fn.shellescape(filepath)))
      :gsub("\n", "")

    if last_commit ~= "" then
      message = message .. "Last commit: " .. last_commit .. "\n"
    end

    -- Check if file is tracked
    local is_tracked =
      vim.fn.system(string.format("git ls-files --error-unmatch %s 2>/dev/null", vim.fn.shellescape(filepath)))

    if vim.v.shell_error ~= 0 then
      message = message .. "Status: Untracked file\n"
    else
      -- Check if file has uncommitted changes
      local has_changes = vim.fn
        .system(string.format("git diff --name-only -- %s 2>/dev/null", vim.fn.shellescape(filepath)))
        :gsub("\n", "")

      local has_staged = vim.fn
        .system(string.format("git diff --cached --name-only -- %s 2>/dev/null", vim.fn.shellescape(filepath)))
        :gsub("\n", "")

      if has_staged ~= "" then
        message = message .. "Status: Has staged changes\n"
      elseif has_changes ~= "" then
        message = message .. "Status: Has unstaged changes\n"
      else
        message = message .. "Status: Clean (no changes)\n"
      end
    end

    -- Count lines changed in working tree
    local diff_stat =
      vim.fn.system(string.format("git diff --numstat -- %s 2>/dev/null", vim.fn.shellescape(filepath))):gsub("\n", "")

    if diff_stat ~= "" then
      local added, removed = diff_stat:match "(%d+)%s+(%d+)"
      if added and removed then
        message = message .. string.format("Changes: +%s -%s lines\n", added, removed)
      end
    end
  end

  message = message .. config.fyi_suffix
  message = message .. "=== End File Context ===\n\n"

  send_to_claude(message)
end

-- Manually add current directory or git root to Claude
function M.add_current_directory()
  -- Only proceed if Claude is running
  local claude_buf = find_claude_terminal()
  if not claude_buf then
    return
  end

  -- Determine which directory to add
  local dir_to_add = get_git_root() or vim.fn.getcwd()

  -- Check if already added
  if state.added_directories[dir_to_add] then
    vim.notify("Directory already added: " .. dir_to_add, vim.log.levels.INFO)
    return
  end

  -- Mark as added and send command
  state.added_directories[dir_to_add] = true
  local add_dir_msg = string.format("/add-dir %s", dir_to_add)
  send_to_claude(add_dir_msg)

  vim.notify("Added directory to Claude: " .. dir_to_add, vim.log.levels.INFO)
end

-- Setup autocmd for file saves
function M.setup_autocmd()
  vim.api.nvim_create_augroup("ClaudeContext", { clear = true })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = "ClaudeContext",
    pattern = "*",
    callback = function()
      if not config.enabled then
        return
      end

      -- Skip certain files
      local filepath = vim.fn.expand "%:p"
      if filepath:match "%.git/" or filepath:match "node_modules/" or filepath:match "%.log$" then
        return
      end

      -- Only send if Claude is running
      local buf = find_claude_terminal()
      if buf then
        M.send_context()
      end
    end,
    desc = "Send git diff to Claude on file save",
  })

  -- Removed automatic directory adding - use :ClaudeAddDir manually instead
end

-- Initialize
function M.setup()
  -- Create user commands
  vim.api.nvim_create_user_command("ClaudeToggle", M.toggle_claude, {
    desc = "Toggle Claude terminal window",
  })

  vim.api.nvim_create_user_command("ClaudeStop", M.stop_claude, {
    desc = "Stop Claude session completely",
  })

  vim.api.nvim_create_user_command("ClaudeContext", function()
    M.send_context(true) -- Force send, bypassing filters
  end, {
    desc = "Send current file's git diff to Claude (force)",
  })

  vim.api.nvim_create_user_command("ClaudeSay", function(opts)
    local message = opts.args
    local is_command = false

    -- Check if it starts with ! for shell command
    if message:match "^!" then
      local cmd = message:sub(2) -- Remove the !
      -- Expand vim placeholders like % before executing
      cmd = vim.fn.expand(cmd)
      local output = vim.fn.system(cmd)
      message = string.format(
        "\n=== COMMAND EXECUTION ===\nI executed: `%s`\n\nOutput:\n```\n%s```\n\nDO NOT take any action. Just acknowledge. Stand by for further instructions.\n=== END ===\n",
        cmd,
        output
      )
      is_command = true
    -- Check if it starts with : for vim command
    elseif message:match "^:" then
      local cmd = message:sub(2) -- Remove the :
      local output = vim.fn.execute(cmd)
      message = string.format(
        "\n=== VIM COMMAND EXECUTION ===\nI executed: `:%s`\n\nOutput:\n```\n%s```\n\nDO NOT take any action. Just acknowledge. Stand by for further instructions.\n=== END ===\n",
        cmd,
        output
      )
      is_command = true
    else
      -- For regular messages, also expand vim placeholders
      message = vim.fn.expand(message)
    end

    -- Send the message
    M.send_message(message)

    -- If it was a command, give Claude time to process before we continue
    if is_command then
      vim.defer_fn(function()
        -- Just a pause to let Claude process the output
      end, 1000)
    end
  end, {
    nargs = "+",
    desc = "Send message to Claude (! for shell, : for vim command)",
  })

  vim.api.nvim_create_user_command("ClaudeToggleGitDiffSend", M.toggle_git_diff_send, {
    desc = "Toggle automatic git diff sending on file save",
  })

  vim.api.nvim_create_user_command("ClaudeStatus", M.send_git_status, {
    desc = "Send comprehensive git status with diffs to Claude",
  })

  vim.api.nvim_create_user_command("ClaudeStartUpdates", function(opts)
    local interval = tonumber(opts.args) or 10
    M.start_periodic_updates(interval)
    vim.notify("Started periodic updates every " .. interval .. " minutes", vim.log.levels.INFO)
  end, {
    nargs = "?",
    desc = "Start periodic status updates (default 10 min)",
  })

  vim.api.nvim_create_user_command("ClaudeStopUpdates", function()
    M.stop_periodic_updates()
    vim.notify("Stopped periodic updates", vim.log.levels.INFO)
  end, {
    desc = "Stop periodic status updates",
  })

  vim.api.nvim_create_user_command("ClaudeReadUnstaged", M.send_unstaged_files, {
    desc = "Ask Claude to read untracked/unstaged files",
  })

  vim.api.nvim_create_user_command("ClaudeFileInfo", M.send_file_info, {
    desc = "Send current file's git info and metadata to Claude",
  })

  vim.api.nvim_create_user_command("ClaudeAddDir", M.add_current_directory, {
    desc = "Add current git root or working directory to Claude",
  })

  vim.api.nvim_create_user_command("ClaudeToggleLSP", function()
    config.lsp_enabled = not config.lsp_enabled
    local status = config.lsp_enabled and "enabled" or "disabled"
    vim.notify("Claude LSP integration " .. status, vim.log.levels.INFO)

    -- If enabled, send current buffer's LSP context immediately
    if config.lsp_enabled then
      local bufnr = vim.api.nvim_get_current_buf()
      local lsp_context = get_lsp_context(bufnr)
      if lsp_context and #lsp_context.diagnostics > 0 then
        local filepath = vim.fn.expand "%:t"
        local message = "\n=== LSP Integration Enabled ===\n"
        message = message .. "Current file: " .. filepath .. "\n"
        message = message .. format_lsp_context(lsp_context, filepath)
        message = message .. config.fyi_suffix
        message = message .. "=== End LSP Status ===\n\n"
        send_to_claude(message)
      end
    end
  end, {
    desc = "Toggle LSP semantic context integration",
  })

  -- Setup autocmd
  M.setup_autocmd()

  -- Auto-reload files when changed externally (by Claude)
  vim.o.autoread = true
  vim.o.updatetime = 1000 -- Check for file changes every 1 second when idle

  -- Event-based reload
  vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
    pattern = "*",
    callback = function()
      if vim.fn.mode() ~= "c" then
        vim.cmd "checktime"
      end
    end,
    desc = "Auto-reload files changed by Claude",
  })

  -- Aggressive timer-based reload (checks every 500ms regardless of cursor movement)
  local reload_timer = vim.loop.new_timer()
  reload_timer:start(
    500,
    500,
    vim.schedule_wrap(function()
      if vim.fn.mode() ~= "c" then
        vim.cmd "silent! checktime"
      end
    end)
  )

  -- Optional keybindings (you can customize these)
  vim.keymap.set("n", "<leader>ct", M.toggle_claude, { desc = "Toggle Claude window" })
  vim.keymap.set("n", "<leader>cc", function()
    M.send_context(true)
  end, { desc = "Send context to Claude (force)" })
  vim.keymap.set("n", "<leader>cd", M.toggle_git_diff_send, { desc = "Toggle Claude diff sending" })
  vim.keymap.set("n", "<leader>cu", M.send_unstaged_files, { desc = "Send unstaged files list to Claude" })
  vim.keymap.set("n", "<leader>cg", M.send_git_status, { desc = "Send comprehensive git status to Claude" })
  vim.keymap.set("n", "<leader>cs", ":ClaudeSay ", { desc = "Say something to Claude" })
  vim.keymap.set("n", "<leader>cf", M.send_file_info, { desc = "Send current file info to Claude" })

  -- Initialize indicator
  update_indicator()
end

-- Auto-setup when module loads
M.setup()

return M
