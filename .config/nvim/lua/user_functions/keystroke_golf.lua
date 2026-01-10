-- Keystroke Golf: Compare different approaches by counting keystrokes
-- <leader>rs - start/stop recording
-- <leader>rx - reset (clear all recordings)

local M = {}

local state = {
  recording = false,
  current_keys = {},
  current_count = 0,
  ledger = {}, -- { { timestamp, count, keys }, ... }
  namespace = nil,
  buf = nil,
  win = nil,
  last_key = nil,
  last_time = 0,
}

local function get_namespace()
  if not state.namespace then
    state.namespace = vim.api.nvim_create_namespace "keystroke_golf"
  end
  return state.namespace
end

-- Keys to ignore (internal neovim events, not actual keypresses)
local ignore_keys = {
  ["<Cmd>"] = true,
  ["<Plug>"] = true,
  ["<SNR>"] = true,
  ["<SID>"] = true,
}

local function build_lines()
  local lines = {}

  -- Show recording status
  if state.recording then
    table.insert(lines, "🔴 Recording... (do your edit, then <leader>rs to stop)")
  end

  if #state.ledger == 0 then
    if not state.recording then
      table.insert(lines, "Keystroke Golf - <leader>rs to start recording")
    end
    return lines
  end

  -- Sort by count to find rankings
  local ranked = {}
  for i, entry in ipairs(state.ledger) do
    table.insert(ranked, { idx = i, entry = entry })
  end
  table.sort(ranked, function(a, b)
    return a.entry.count < b.entry.count
  end)

  for rank, item in ipairs(ranked) do
    local prefix = rank == 1 and "🏆" or string.format("%2d", rank)
    local line = string.format(
      "%s #%d [%s] %3d keys: %s",
      prefix,
      item.idx,
      item.entry.timestamp,
      item.entry.count,
      #item.entry.keys > 50 and item.entry.keys:sub(1, 50) .. "…" or item.entry.keys
    )
    table.insert(lines, line)
  end
  return lines
end

local function refresh_display()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  local lines = build_lines()
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  -- Resize window to fit content
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_height(state.win, math.min(10, #lines + 1))
  end
end

local function is_win_open()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function on_key(_, typed)
  if not state.recording then
    return
  end
  if not typed or typed == "" then
    return
  end
  local translated = vim.fn.keytrans(typed)
  if not translated or translated == "" then
    return
  end
  -- For text objects, typed can be multi-char (e.g., "ip" for inner paragraph)
  -- Only take the last actual keypress to avoid double-counting
  if #translated > 1 and not translated:match "^<.*>$" then
    translated = translated:sub(-1)
  end
  -- Skip internal neovim keys
  for prefix, _ in pairs(ignore_keys) do
    if translated:find("^" .. prefix:gsub("[<>]", "%%%1")) then
      return
    end
  end
  -- Deduplicate rapid consecutive identical keys (vim.on_key sometimes fires twice)
  local now = vim.loop.hrtime() / 1e6 -- ms
  if translated == state.last_key and (now - state.last_time) < 50 then
    return
  end
  state.last_key = translated
  state.last_time = now

  table.insert(state.current_keys, translated)
  state.current_count = state.current_count + 1
end

local function ends_with(str, suffix)
  return str:sub(-#suffix) == suffix
end

local function strip_toggle_keys(keys)
  local str = table.concat(keys, "")
  -- Strip trailing toggle sequences (fixed strings, not patterns)
  local suffixes = { "<Space>rs", "<Space>rx", " rs", " rx" }
  local changed = true
  while changed do
    changed = false
    for _, suffix in ipairs(suffixes) do
      if ends_with(str, suffix) then
        str = str:sub(1, -#suffix - 1)
        changed = true
        break
      end
    end
  end
  -- Rebuild array
  local result = {}
  local i = 1
  while i <= #str do
    if str:sub(i, i) == "<" then
      local j = str:find(">", i, true) -- plain search
      if j then
        table.insert(result, str:sub(i, j))
        i = j + 1
      else
        table.insert(result, str:sub(i, i))
        i = i + 1
      end
    else
      table.insert(result, str:sub(i, i))
      i = i + 1
    end
  end
  for j = 1, #keys do
    keys[j] = nil
  end
  for j, v in ipairs(result) do
    keys[j] = v
  end
  return keys
end

function M.toggle_recording()
  if state.recording then
    vim.on_key(nil, get_namespace())
    state.recording = false

    strip_toggle_keys(state.current_keys)
    state.current_count = #state.current_keys

    if state.current_count > 0 then
      table.insert(state.ledger, {
        timestamp = os.date "%H:%M:%S",
        count = state.current_count,
        keys = table.concat(state.current_keys, ""),
      })
    end
    refresh_display()
  else
    state.current_keys = {}
    state.current_count = 0
    state.recording = true
    vim.on_key(on_key, get_namespace())
    -- Auto-open panel if not visible, otherwise just refresh
    if not is_win_open() then
      M.toggle_panel()
    else
      refresh_display()
    end
  end
end

local function delete_current_entry()
  local line = vim.api.nvim_get_current_line()
  local idx = line:match "#(%d+)"
  if idx then
    idx = tonumber(idx)
    if idx and state.ledger[idx] then
      table.remove(state.ledger, idx)
      refresh_display()
    end
  end
end

function M.toggle_panel()
  if is_win_open() then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
    return
  end

  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype = "nofile"
    vim.bo[state.buf].bufhidden = "hide"
    vim.bo[state.buf].swapfile = false
    vim.api.nvim_buf_set_name(state.buf, "Keystroke Golf")
    vim.keymap.set("n", "q", M.toggle_panel, { buffer = state.buf, desc = "close panel" })
    vim.keymap.set("n", "dd", delete_current_entry, { buffer = state.buf, desc = "delete entry" })
  end

  vim.cmd "botright split"
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_win_set_height(state.win, math.min(10, #state.ledger + 2))
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].winfixheight = true

  refresh_display()
  vim.cmd "wincmd p"
end

function M.show_ledger()
  M.toggle_panel()
end

function M.clear_ledger()
  state.ledger = {}
  refresh_display()
end

function M.setup()
  vim.keymap.set("n", "<leader>rs", M.toggle_recording, { desc = "keystroke golf: start/stop" })
  vim.keymap.set("n", "<leader>rx", M.clear_ledger, { desc = "keystroke golf: reset" })
end

return M
