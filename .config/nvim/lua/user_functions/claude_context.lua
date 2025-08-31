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
    ignore_whitespace_only = true,   -- Skip pure formatting changes
    ignore_comment_only = false,      -- Keep comments - they show intent
    min_change_lines = 0,             -- Send all real changes
    batch_delay_ms = 1500,            -- 1.5s delay to group related saves
  },
  -- Track files Claude has worked on
  relevant_files = {},
  pending_updates = {},
}

-- State
local state = {
  claude_buf = nil,
  claude_job_id = nil,
  claude_win = nil,
  session_start = os.time(),
  last_status_update = 0,
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
    if line:match("^%+[^%+]") then
      added_lines = added_lines + 1
      -- Check if it's more than just whitespace
      if line:match("%S") then
        has_non_whitespace = true
      end
      -- Check if it's not just a comment (basic check for common languages)
      if not line:match("^%+%s*//") and 
         not line:match("^%+%s*#") and 
         not line:match("^%+%s*%-%-") and
         not line:match("^%+%s*%*") then
        has_non_comment = true
      end
    elseif line:match("^%-[^%-]") then
      removed_lines = removed_lines + 1
      if line:match("%S") then
        has_non_whitespace = true
      end
      if not line:match("^%-%s*//") and 
         not line:match("^%-%s*#") and 
         not line:match("^%-%s*%-%-") and
         not line:match("^%-%s*%*") then
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
    vim.g.claude_context_indicator = ''  -- Claude not running
  elseif config.enabled then
    vim.g.claude_context_indicator = '[C]'  -- Claude active, diffs on
  else
    vim.g.claude_context_indicator = '[C-off]'  -- Claude active, diffs off
  end
end

-- Helper: Format context update message
local function format_context_update(filepath, diff)
  local timestamp = os.date("%H:%M:%S")
  local message = string.format(
    "\n=== FYI: Context Update [%s] ===\nFile saved: %s\n",
    timestamp,
    filepath
  )
  
  -- Get list of other modified files (just names, keep it simple)
  local git_status = vim.fn.system("git status --porcelain 2>/dev/null")
  if git_status ~= "" then
    local other_files = {}
    local current_file = vim.fn.fnamemodify(filepath, ':.')  -- Make filepath relative for comparison
    
    for line in git_status:gmatch("[^\n]+") do
      local filename = line:match("^.. (.+)$")
      if filename and filename ~= current_file then
        table.insert(other_files, filename)
      end
    end
    
    if #other_files > 0 then
      message = message .. "Also modified: " .. table.concat(other_files, ", ") .. "\n"
    end
  end
  
  message = message .. "DO NOT take any action. This is ONLY for your awareness. Wait for explicit instructions.\n"
  
  if diff and diff ~= "" then
    -- Clean up the diff output
    local lines = vim.split(diff, "\n")
    local clean_diff = {}
    for _, line in ipairs(lines) do
      -- Skip binary file messages and empty lines at the end
      if not line:match("^Binary files") and (line ~= "" or #clean_diff > 0) then
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
    vim.fn.chansend(job_id, string.char(13))  -- ASCII 13 = CR = Enter key
    
    -- Jump to end to maintain autoscroll for next output
    if win then
      vim.api.nvim_win_call(win, function()
        vim.cmd('norm G')
      end)
    end
  end, 500)  -- Half second delay
  
  return true
end

-- Main: Start Claude assistant
function M.start_claude()
  -- Check if already running
  local existing_buf = find_claude_terminal()
  if existing_buf then
    vim.notify("Claude assistant already running", vim.log.levels.INFO)
    return
  end
  
  -- Get current working directory for permissions
  local cwd = vim.fn.getcwd()
  
  -- Build claude command with directory permissions and auto-accept edits
  -- --add-dir grants access to the directory
  -- --permission-mode acceptEdits automatically accepts all file edits without prompting
  local claude_cmd = config.claude_path .. ' --add-dir ' .. vim.fn.shellescape(cwd) .. ' --permission-mode acceptEdits'
  
  -- Open Claude in a vertical split on the left (40% width for Claude, 60% for editor)
  -- The $NVIM environment variable is automatically set by Neovim terminal
  local width = math.floor(vim.o.columns * 0.4)
  vim.cmd('leftabove ' .. width .. 'vsplit term://' .. claude_cmd)
  
  -- Mark this terminal as the Claude assistant
  local buf = vim.api.nvim_get_current_buf()
  vim.b[buf].is_claude_assistant = true
  
  -- Store state
  state.claude_buf = buf
  state.claude_win = vim.api.nvim_get_current_win()
  state.claude_job_id = vim.b[buf].terminal_job_id
  
  -- Start in insert mode for the terminal
  vim.cmd('startinsert')
  
  -- Set autocmd to always enter insert mode when entering this terminal
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      vim.cmd('startinsert')
    end
  })
  
  -- Jump to last line to enable terminal's native autoscroll
  vim.cmd('norm G')
  
  -- Return to previous window but keep terminal in insert mode
  vim.cmd('stopinsert')  -- Stop insert mode for current window
  vim.cmd('wincmd p')
  
  -- Update indicator
  update_indicator()
end

-- Toggle Claude window
function M.toggle_claude()
  local buf, win = find_claude_terminal()
  if win then
    -- Window is visible, hide it (we need to implement this function)
    vim.api.nvim_win_close(win, false)
  elseif buf then
    -- Buffer exists but no window, create one with same split settings
    local width = math.floor(vim.o.columns * 0.4)
    vim.cmd('leftabove ' .. width .. 'vsplit')
    vim.api.nvim_set_current_buf(buf)
    vim.cmd('wincmd p')
  else
    -- No Claude session exists, start one
    M.start_claude()
  end
  update_indicator()  -- Update after toggle
end

-- Batch timer for collecting multiple updates
local batch_timer = nil

-- Send batched updates
local function send_batched_updates()
  if not next(config.pending_updates) then
    return
  end
  
  local timestamp = os.date("%H:%M:%S")
  local message = string.format(
    "\n=== FYI: Batched Context Update [%s] ===\nFiles changed:\n",
    timestamp
  )
  
  for filepath, diff in pairs(config.pending_updates) do
    message = message .. string.format("• %s\n", filepath)
  end
  
  -- Get ALL modified files in workspace
  local git_status = vim.fn.system("git status --porcelain 2>/dev/null")
  if git_status ~= "" then
    local all_modified = {}
    for line in git_status:gmatch("[^\n]+") do
      local filename = line:match("^.. (.+)$")
      if filename and not config.pending_updates[filename] then
        table.insert(all_modified, filename)
      end
    end
    
    if #all_modified > 0 then
      message = message .. "\nAlso modified in workspace:\n"
      for _, file in ipairs(all_modified) do
        message = message .. string.format("• %s\n", file)
      end
    end
  end
  
  message = message .. "\nChanges:\n"
  
  for filepath, diff in pairs(config.pending_updates) do
    message = message .. string.format("\n--- %s ---\n```diff\n%s\n```\n", filepath, diff)
  end
  
  message = message .. "DO NOT take any action. This is ONLY for context. Wait for instructions.\n"
  message = message .. "=== End Context Update ===\n\n"
  
  send_to_claude(message)
  config.pending_updates = {}
end

-- Send current file context (with smart filtering)
function M.send_context(force)
  local filepath = vim.fn.expand('%:p')
  local relative_path = vim.fn.fnamemodify(filepath, ':.')
  
  
  -- Get UNSTAGED changes only (not showing already staged work)
  -- This way, once you stage completed work, Claude only sees new changes
  local diff_cmd = string.format(
    'git diff --unified=%d -- %s',
    config.diff_context_lines,
    vim.fn.shellescape(filepath)
  )
  local diff = vim.fn.system(diff_cmd)
  
  -- Check if diff is significant
  if not force and not is_significant_diff(diff) then
    return
  end
  
  -- If batching is enabled, add to pending updates
  if config.filter.batch_delay_ms > 0 and not force then
    config.pending_updates[relative_path] = diff
    
    -- Cancel existing timer
    if batch_timer then
      batch_timer:stop()
    end
    
    -- Start new timer
    batch_timer = vim.loop.new_timer()
    batch_timer:start(config.filter.batch_delay_ms, 0, vim.schedule_wrap(function()
      send_batched_updates()
      batch_timer = nil
    end))
  else
    -- Send immediately
    local message = format_context_update(relative_path, diff)
    send_to_claude(message)
  end
end

-- Send arbitrary message
function M.send_message(message)
  if message and message ~= "" then
    send_to_claude("\n>>> " .. message .. "\n\n")
  end
end

-- Send comprehensive git status with all diffs
function M.send_git_status()
  local timestamp = os.date("%H:%M:%S")
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
    local ahead, behind = rev_list:match("(%d+)%s+(%d+)")
    if ahead and behind then
      message = message .. string.format("↑ %s ahead, ↓ %s behind upstream\n", ahead, behind)
    end
  end
  
  -- File status summary
  local status = vim.fn.system("git status --porcelain 2>/dev/null")
  local staged_files = {}
  local unstaged_files = {}
  local untracked_files = {}
  
  for line in status:gmatch("[^\n]+") do
    local status_code = line:sub(1, 2)
    local filename = line:sub(4)
    
    if status_code:match("^[MADRC]") then
      table.insert(staged_files, filename)
    end
    if status_code:match(".[MD]") then
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
  local staged_diff = vim.fn.system("git diff --cached --stat 2>/dev/null")
  if staged_diff ~= "" then
    message = message .. "\nSTAGED CHANGES (will be committed):\n```\n" .. staged_diff .. "```\n"
    
    -- Show actual staged diff (limited)
    local staged_diff_full = vim.fn.system("git diff --cached --unified=3 2>/dev/null")
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
  local unstaged_diff = vim.fn.system("git diff --stat 2>/dev/null")
  if unstaged_diff ~= "" then
    message = message .. "\nUNSTAGED CHANGES (working directory):\n```\n" .. unstaged_diff .. "```\n"
    
    -- Show actual unstaged diff (limited)
    local unstaged_diff_full = vim.fn.system("git diff --unified=3 2>/dev/null")
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
  local commits = vim.fn.system("git log --oneline -10 2>/dev/null")
  if commits ~= "" then
    message = message .. "\nRECENT COMMITS:\n```\n" .. commits .. "```\n"
  end
  
  -- Stash status
  local stash = vim.fn.system("git stash list 2>/dev/null")
  if stash ~= "" then
    local stash_count = select(2, stash:gsub("\n", "\n"))
    message = message .. "\nSTASHES: " .. stash_count .. " stashed changes\n"
  end
  
  message = message .. "\nThis is FYI only - DO NOT take any action based on this information.\n"
  message = message .. "Stay responsive and wait for my explicit instructions.\n"
  message = message .. "=== End Overview ===\n\n"
  
  send_to_claude(message)
end

-- Send untracked/unstaged files for Claude to read
function M.send_unstaged_files()
  local timestamp = os.date("%H:%M:%S")
  local git_status = vim.fn.system("git status --porcelain 2>/dev/null")
  
  if git_status == "" then
    vim.notify("No changes in working directory", vim.log.levels.INFO)
    return
  end
  
  local untracked_files = {}
  local modified_files = {}
  
  for line in git_status:gmatch("[^\n]+") do
    local status_code = line:sub(1, 2)
    local filename = line:sub(4)  -- Skip status codes and space
    
    if status_code == "??" then
      table.insert(untracked_files, filename)
    elseif status_code:match("[MA ]M") or status_code:match("M[MD ]") then
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
  message = message .. "DO NOT read them automatically - wait for my instructions.\n"
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
  
  status_timer:start(interval_ms, interval_ms, vim.schedule_wrap(function()
    local buf = find_claude_terminal()
    if buf then
      M.send_git_status()
    end
  end))
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
  update_indicator()  -- Update lualine indicator
end

-- Setup autocmd for file saves
function M.setup_autocmd()
  vim.api.nvim_create_augroup("ClaudeContext", { clear = true })
  
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = "ClaudeContext",
    pattern = "*",
    callback = function()
      if not config.enabled then return end
      
      -- Skip certain files
      local filepath = vim.fn.expand('%:p')
      if filepath:match("%.git/") or 
         filepath:match("node_modules/") or
         filepath:match("%.log$") then
        return
      end
      
      -- Only send if Claude is running
      local buf = find_claude_terminal()
      if buf then
        M.send_context()
      end
    end,
    desc = "Send git diff to Claude on file save"
  })
end

-- Initialize
function M.setup()
  -- Create user commands
  vim.api.nvim_create_user_command('ClaudeStart', M.start_claude, {
    desc = "Start Claude assistant in terminal"
  })
  
  vim.api.nvim_create_user_command('ClaudeToggle', M.toggle_claude, {
    desc = "Toggle Claude terminal window"
  })
  
  vim.api.nvim_create_user_command('ClaudeContext', function()
    M.send_context(true)  -- Force send, bypassing filters
  end, {
    desc = "Send current file's git diff to Claude (force)"
  })
  
  vim.api.nvim_create_user_command('ClaudeSay', function(opts)
    local message = opts.args
    local is_command = false
    
    -- Check if it starts with ! for shell command
    if message:match("^!") then
      local cmd = message:sub(2)  -- Remove the !
      local output = vim.fn.system(cmd)
      message = string.format(
        "\n=== COMMAND EXECUTION ===\nI executed: `%s`\n\nOutput:\n```\n%s```\n\nDO NOT take any action. Just acknowledge. Stand by for further instructions.\n=== END ===\n", 
        cmd, output
      )
      is_command = true
    -- Check if it starts with : for vim command  
    elseif message:match("^:") then
      local cmd = message:sub(2)  -- Remove the :
      local output = vim.fn.execute(cmd)
      message = string.format(
        "\n=== VIM COMMAND EXECUTION ===\nI executed: `:%s`\n\nOutput:\n```\n%s```\n\nDO NOT take any action. Just acknowledge. Stand by for further instructions.\n=== END ===\n", 
        cmd, output
      )
      is_command = true
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
    nargs = '+',
    desc = "Send message to Claude (! for shell, : for vim command)"
  })
  
  vim.api.nvim_create_user_command('ClaudeToggleGitDiffSend', M.toggle_git_diff_send, {
    desc = "Toggle automatic git diff sending on file save"
  })
  
  vim.api.nvim_create_user_command('ClaudeStatus', M.send_git_status, {
    desc = "Send comprehensive git status with diffs to Claude"
  })
  
  vim.api.nvim_create_user_command('ClaudeStartUpdates', function(opts)
    local interval = tonumber(opts.args) or 10
    M.start_periodic_updates(interval)
    vim.notify("Started periodic updates every " .. interval .. " minutes", vim.log.levels.INFO)
  end, {
    nargs = '?',
    desc = "Start periodic status updates (default 10 min)"
  })
  
  vim.api.nvim_create_user_command('ClaudeStopUpdates', function()
    M.stop_periodic_updates()
    vim.notify("Stopped periodic updates", vim.log.levels.INFO)
  end, {
    desc = "Stop periodic status updates"
  })
  
  vim.api.nvim_create_user_command('ClaudeReadUnstaged', M.send_unstaged_files, {
    desc = "Ask Claude to read untracked/unstaged files"
  })
  
  -- Setup autocmd
  M.setup_autocmd()
  
  -- Auto-reload files when changed externally (by Claude)
  vim.o.autoread = true
  vim.o.updatetime = 1000  -- Check for file changes every 1 second when idle
  
  -- Event-based reload
  vim.api.nvim_create_autocmd({"FocusGained", "BufEnter", "CursorHold", "CursorHoldI"}, {
    pattern = "*",
    callback = function()
      if vim.fn.mode() ~= "c" then
        vim.cmd("checktime")
      end
    end,
    desc = "Auto-reload files changed by Claude"
  })
  
  -- Aggressive timer-based reload (checks every 500ms regardless of cursor movement)
  local reload_timer = vim.loop.new_timer()
  reload_timer:start(500, 500, vim.schedule_wrap(function()
    if vim.fn.mode() ~= "c" then
      vim.cmd("silent! checktime")
    end
  end))
  
  -- Optional keybindings (you can customize these)
  vim.keymap.set('n', '<leader>cs', M.start_claude, { desc = "Start Claude" })
  vim.keymap.set('n', '<leader>ct', M.toggle_claude, { desc = "Toggle Claude window" })
  vim.keymap.set('n', '<leader>cc', function() M.send_context(true) end, { desc = "Send context to Claude (force)" })
  vim.keymap.set('n', '<leader>cd', M.toggle_git_diff_send, { desc = "Toggle Claude diff sending" })
  vim.keymap.set('n', '<leader>cu', M.send_unstaged_files, { desc = "Send unstaged files list to Claude" })
  vim.keymap.set('n', '<leader>cg', M.send_git_status, { desc = "Send comprehensive git status to Claude" })
  
  -- Initialize indicator
  update_indicator()
end

-- Auto-setup when module loads
M.setup()

return M