-- Markdown reading mode: <leader>mr switches the current buffer between
-- editing and a view made for reading, navigating and copying. Nothing is
-- added to the file. List items get visual gaps (paragraphs.lua); headings,
-- labels and acronyms get colours and render-markdown renders the text
-- (style.lua). } and { step item by item and ip/ap select one item, as if the
-- gaps were blank lines. The window drops its gutter and spell marks for this
-- buffer. <leader>mo picks a link, <leader>mh picks a heading and <CR> follows
-- the link under the cursor (links.lua). The buffer is read-only while
-- reading, since markup hidden by the rendering (link targets, ** around bold)
-- is easy to break unseen; the gaps and colours follow changes on disk. q or
-- <leader>mr returns to editing.
local paragraphs = require "markdown_reader.paragraphs"
local style = require "markdown_reader.style"
local links = require "markdown_reader.links"

local M = {}

M.links = links.links
M.pick_links = links.pick_links
M.pick_headings = links.pick_headings

local reading_values = {
  number = false,
  relativenumber = false,
  signcolumn = "no",
  foldcolumn = "2",
  cursorline = false,
  spell = false,
  colorcolumn = "",
  list = false,
}

-- Reading state per buffer: saved window options and key maps, the augroup,
-- and the current gaps.
local state = {}

-- Whether `buf` (default: the current buffer) is in reading mode.
function M.is_reading(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  return state[buf] ~= nil
end

local function buf_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

-- Recompute the gaps and colours of `buf` after its text changed.
function M.refresh(buf)
  local st = state[buf]
  if not (st and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local lines = buf_lines(buf)
  st.gaps = paragraphs.gaps(lines)
  style.mark_gaps(buf, st.gaps)
  style.mark_words(buf, lines)
end

-- Put `row` of window `w`'s buffer at screen line `winline` (0 is the top).
local function place(w, row, winline, col)
  local buf = vim.api.nvim_win_get_buf(w)
  row = math.max(1, math.min(row, vim.api.nvim_buf_line_count(buf)))
  local top = row
  while top > 1 do
    local above = vim.api.nvim_win_text_height(w, { start_row = top - 2, end_row = row - 2 }).all
    if above > winline then
      break
    end
    top = top - 1
  end
  vim.api.nvim_win_call(w, function()
    vim.fn.winrestview { lnum = row, col = col or 0, curswant = col or 0, topline = top }
  end)
end

-- } and {: the next or previous paragraph stop, counting gaps.
local function move(forward)
  local buf = vim.api.nvim_get_current_buf()
  local lines, row = buf_lines(buf), vim.api.nvim_win_get_cursor(0)[1]
  for _ = 1, vim.v.count1 do
    row = paragraphs.stop(lines, state[buf].gaps, row, forward)
  end
  if vim.api.nvim_get_mode().mode == "n" then
    vim.cmd "normal! m'"
  end
  local col = 0
  if forward and row == #lines and lines[row] ~= "" then
    col = #lines[row] - 1
  end
  vim.api.nvim_win_set_cursor(0, { row, col })
end

-- ip and ap: select the paragraph at the cursor line by line, counting gaps.
local function select(around)
  local buf = vim.api.nvim_get_current_buf()
  local first, last = paragraphs.paragraph(buf_lines(buf), state[buf].gaps, vim.api.nvim_win_get_cursor(0)[1], around)
  if vim.api.nvim_get_mode().mode:match "^[vV\22]" then
    vim.cmd("normal! " .. vim.keycode "<Esc>")
  end
  vim.api.nvim_win_set_cursor(0, { first, 0 })
  vim.cmd "normal! V"
  vim.api.nvim_win_set_cursor(0, { last, 0 })
end

-- Switch the current buffer to reading mode, keeping the cursor line at the
-- same height in the window.
function M.enter()
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  if state[buf] then
    return
  end
  local pos, winline = vim.api.nvim_win_get_cursor(win), vim.fn.winline() - 1
  local st = { wo = {}, maps = {}, modifiable = vim.bo[buf].modifiable }
  state[buf] = st
  vim.bo[buf].modifiable = false

  for name, value in pairs(reading_values) do
    st.wo[name] = vim.api.nvim_get_option_value(name, { scope = "local", win = win })
    vim.api.nvim_set_option_value(name, value, { scope = "local", win = win })
  end

  local function map(modes, lhs, rhs)
    for _, mode in ipairs(type(modes) == "table" and modes or { modes }) do
      local old = vim.fn.maparg(lhs, mode, false, true)
      st.maps[#st.maps + 1] = { mode = mode, lhs = lhs, old = old.buffer == 1 and old or nil }
      vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true })
    end
  end
  map("n", "q", M.leave)
  map("n", "<CR>", links.follow)
  map({ "n", "x", "o" }, "}", function()
    move(true)
  end)
  map({ "n", "x", "o" }, "{", function()
    move(false)
  end)
  map({ "x", "o" }, "ip", function()
    select(false)
  end)
  map({ "x", "o" }, "ap", function()
    select(true)
  end)

  st.group = vim.api.nvim_create_augroup("markdown_reader_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufReadPost", "FileChangedShellPost" }, {
    group = st.group,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        M.refresh(buf)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = st.group,
    buffer = buf,
    callback = function()
      state[buf] = nil
    end,
  })

  style.set_highlights()
  M.refresh(buf)
  style.tune_render(buf)
  place(win, pos[1], winline, pos[2])
end

-- Switch the current buffer back to editing: window options, key maps and
-- rendering as they were.
function M.leave()
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local st = state[buf]
  if not st then
    return
  end
  local pos, winline = vim.api.nvim_win_get_cursor(win), vim.fn.winline() - 1
  state[buf] = nil
  vim.bo[buf].modifiable = st.modifiable
  for name, value in pairs(st.wo) do
    vim.api.nvim_set_option_value(name, value, { scope = "local", win = win })
  end
  for _, m in ipairs(st.maps) do
    pcall(vim.keymap.del, m.mode, m.lhs, { buffer = buf })
    if m.old then
      pcall(vim.fn.mapset, m.mode, false, m.old)
    end
  end
  pcall(vim.api.nvim_del_augroup_by_id, st.group)
  style.clear(buf)
  pcall(function()
    require("render-markdown").buf_disable()
  end)
  place(win, pos[1], winline, pos[2])
end

function M.toggle()
  if M.is_reading() then
    M.leave()
  else
    M.enter()
  end
end

return M
