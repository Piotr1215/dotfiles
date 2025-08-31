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

-- Helper: Mark file as relevant (Claude has worked on it)
function M.mark_relevant(filepath)
  config.relevant_files[filepath] = true
end

-- Helper: Check if file is relevant
local function is_relevant_file(filepath)
  -- If we're tracking relevant files and this isn't one, skip it
  if next(config.relevant_files) and not config.relevant_files[filepath] then
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

-- Helper: Format context update message
local function format_context_update(filepath, diff)
  local timestamp = os.date("%H:%M:%S")
  local message = string.format(
    "\n=== FYI: Context Update [%s] ===\nFile saved: %s\nNo action needed - this is just for your awareness.\n",
    timestamp,
    filepath
  )
  
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

-- Alternative: Use registers and paste
function M.send_context_via_paste()
  local filepath = vim.fn.expand('%:p')
  local relative_path = vim.fn.fnamemodify(filepath, ':.')
  
  -- Get git diff
  local diff_cmd = string.format(
    'git diff --unified=%d HEAD -- %s',
    config.diff_context_lines,
    vim.fn.shellescape(filepath)
  )
  local diff = vim.fn.system(diff_cmd)
  
  if diff == "" then
    diff_cmd = string.format(
      'git diff --unified=%d -- %s',
      config.diff_context_lines,
      vim.fn.shellescape(filepath)
    )
    diff = vim.fn.system(diff_cmd)
  end
  
  local message = format_context_update(relative_path, diff)
  
  -- Put in clipboard
  vim.fn.setreg("+", message)
  
  -- Find and focus Claude window
  local buf, win = find_claude_terminal()
  if win then
    vim.api.nvim_set_current_win(win)
    vim.cmd('startinsert')
    -- Try to paste using terminal paste command
    vim.cmd('normal! "+p')
  end
  
  vim.notify("Context in clipboard - paste it in Claude!", vim.log.levels.INFO)
end

-- Main: Start Claude assistant
function M.start_claude()
  -- Check if already running
  local existing_buf = find_claude_terminal()
  if existing_buf then
    vim.notify("Claude assistant already running", vim.log.levels.INFO)
    M.show_claude()
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
end

-- Show/focus Claude window
function M.show_claude()
  local buf, win = find_claude_terminal()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.notify("Claude assistant not running. Use :ClaudeStart to begin.", vim.log.levels.WARN)
  end
end

-- Hide Claude window
function M.hide_claude()
  local buf, win = find_claude_terminal()
  if win then
    vim.api.nvim_win_close(win, false)
    vim.notify("Claude window hidden (still running)", vim.log.levels.INFO)
  end
end

-- Toggle Claude window
function M.toggle_claude()
  local buf, win = find_claude_terminal()
  if win then
    -- Window is visible, hide it
    M.hide_claude()
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
  
  message = message .. "\nChanges:\n"
  
  for filepath, diff in pairs(config.pending_updates) do
    message = message .. string.format("\n--- %s ---\n```diff\n%s\n```\n", filepath, diff)
  end
  
  message = message .. "=== End Context Update ===\n\n"
  
  send_to_claude(message)
  config.pending_updates = {}
end

-- Send current file context (with smart filtering)
function M.send_context(force)
  local filepath = vim.fn.expand('%:p')
  local relative_path = vim.fn.fnamemodify(filepath, ':.')
  
  -- Check if file is relevant
  if not force and not is_relevant_file(filepath) then
    return
  end
  
  -- Get git diff against HEAD
  local diff_cmd = string.format(
    'git diff --unified=%d HEAD -- %s',
    config.diff_context_lines,
    vim.fn.shellescape(filepath)
  )
  local diff = vim.fn.system(diff_cmd)
  
  -- If no diff against HEAD, try to get uncommitted changes
  if diff == "" then
    diff_cmd = string.format(
      'git diff --unified=%d -- %s',
      config.diff_context_lines,
      vim.fn.shellescape(filepath)
    )
    diff = vim.fn.system(diff_cmd)
  end
  
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

-- Send git status update
function M.send_git_status()
  local timestamp = os.date("%H:%M:%S")
  local message = string.format("\n=== FYI: Git Status [%s] ===\n", timestamp)
  
  -- Current branch
  local branch = vim.fn.system("git branch --show-current 2>/dev/null"):gsub("\n", "")
  if branch ~= "" then
    message = message .. "Branch: " .. branch .. "\n"
  end
  
  -- Status
  local status = vim.fn.system("git status --short 2>/dev/null")
  if status ~= "" then
    message = message .. "\nModified files:\n```\n" .. status .. "```\n"
  end
  
  -- Recent commits
  local commits = vim.fn.system("git log --oneline -5 2>/dev/null")
  if commits ~= "" then
    message = message .. "\nRecent commits:\n```\n" .. commits .. "```\n"
  end
  
  -- Diff stats
  local stats = vim.fn.system("git diff --stat 2>/dev/null")
  if stats ~= "" then
    message = message .. "\nChange summary:\n```\n" .. stats .. "```\n"
  end
  
  message = message .. "=== End Status ===\n\n"
  send_to_claude(message)
end

-- Send work session summary
function M.send_session_summary()
  local timestamp = os.date("%H:%M:%S")
  local session_time = os.difftime(os.time(), state.session_start)
  local minutes = math.floor(session_time / 60)
  
  local message = string.format("\n=== FYI: Session Summary [%s] ===\n", timestamp)
  message = message .. string.format("Session duration: %d minutes\n", minutes)
  
  -- Files changed in this session
  local changed_files = vim.fn.system("git diff --name-only 2>/dev/null")
  if changed_files ~= "" then
    local file_count = select(2, changed_files:gsub("\n", "\n")) 
    message = message .. string.format("\nFiles edited: %d\n", file_count)
    message = message .. "```\n" .. changed_files .. "```\n"
  end
  
  -- Overall stats
  local diff_stat = vim.fn.system("git diff --shortstat 2>/dev/null"):gsub("\n", "")
  if diff_stat ~= "" then
    message = message .. "\nOverall changes: " .. diff_stat .. "\n"
  end
  
  message = message .. "=== End Summary ===\n\n"
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
      M.send_session_summary()
    end
  end))
end

function M.stop_periodic_updates()
  if status_timer then
    status_timer:stop()
    status_timer = nil
  end
end

-- Enable/disable context tracking
function M.toggle_tracking()
  config.enabled = not config.enabled
  local status = config.enabled and "enabled" or "disabled"
  vim.notify("Claude context tracking " .. status, vim.log.levels.INFO)
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
  
  vim.api.nvim_create_user_command('ClaudeShow', M.show_claude, {
    desc = "Show/focus Claude terminal"
  })
  
  vim.api.nvim_create_user_command('ClaudeHide', M.hide_claude, {
    desc = "Hide Claude terminal window"
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
    M.send_message(opts.args)
  end, {
    nargs = '+',
    desc = "Send a message to Claude"
  })
  
  vim.api.nvim_create_user_command('ClaudeToggleTracking', M.toggle_tracking, {
    desc = "Toggle automatic context tracking"
  })
  
  vim.api.nvim_create_user_command('ClaudeMarkRelevant', function()
    local filepath = vim.fn.expand('%:p')
    M.mark_relevant(filepath)
    vim.notify("Marked " .. vim.fn.fnamemodify(filepath, ':.') .. " as relevant to Claude", vim.log.levels.INFO)
  end, {
    desc = "Mark current file as relevant for Claude context"
  })
  
  vim.api.nvim_create_user_command('ClaudeClearRelevant', function()
    config.relevant_files = {}
    vim.notify("Cleared all relevant file markers", vim.log.levels.INFO)
  end, {
    desc = "Clear all relevant file markers"
  })
  
  vim.api.nvim_create_user_command('ClaudeSetBatchDelay', function(opts)
    local delay = tonumber(opts.args)
    if delay then
      config.filter.batch_delay_ms = delay
      vim.notify("Batch delay set to " .. delay .. "ms", vim.log.levels.INFO)
    end
  end, {
    nargs = 1,
    desc = "Set batch delay in milliseconds (0 to disable)"
  })
  
  vim.api.nvim_create_user_command('ClaudeStatus', M.send_git_status, {
    desc = "Send git status to Claude"
  })
  
  vim.api.nvim_create_user_command('ClaudeSummary', M.send_session_summary, {
    desc = "Send work session summary to Claude"
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
  
  vim.api.nvim_create_user_command('ClaudeTest', function()
    -- Test different enter methods
    local buf, win, job_id = find_claude_terminal()
    if job_id then
      vim.notify("Testing enter methods...", vim.log.levels.INFO)
      -- Test 1: Just newline
      vim.api.nvim_chan_send(job_id, "Test 1: newline\n")
      vim.defer_fn(function()
        -- Test 2: Carriage return
        vim.api.nvim_chan_send(job_id, "Test 2: CR" .. string.char(13))
      end, 1000)
      vim.defer_fn(function()
        -- Test 3: Both
        vim.api.nvim_chan_send(job_id, "Test 3: CRLF\r\n")
      end, 2000)
    end
  end, {
    desc = "Test different enter key methods"
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
  vim.keymap.set('n', '<leader>ct', M.toggle_claude, { desc = "Toggle Claude" })
  vim.keymap.set('n', '<leader>cc', M.send_context, { desc = "Send context to Claude" })
end

-- Auto-setup when module loads
M.setup()

return M