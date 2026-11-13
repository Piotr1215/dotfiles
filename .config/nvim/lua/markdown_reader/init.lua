-- Markdown reading mode: <leader>mr swaps the current window to a reading copy
-- of the file and back. The copy is a listed scratch buffer (buffer switching
-- returns to it) with spaced list items (copy.lua), coloured headings, labels
-- and acronyms, always rendered (style.lua). <leader>mo picks a link,
-- <leader>mh picks a heading and <CR> follows the link under the cursor
-- (links.lua). It has no gutter or spell marks and is read-only, and it
-- refreshes when the source changes. <leader>mr, <C-p> and <C-n> swap the
-- window between the file and the copy at the same line, column and height.
-- q returns to the file and closes the copy.
local copy = require "markdown_reader.copy"
local style = require "markdown_reader.style"
local links = require "markdown_reader.links"

local M = {}
local follow

M.spaced_lines = copy.spaced_lines
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

-- Whether the current buffer is a reading copy.
function M.is_reading(buf)
  return vim.b[buf or 0].markdown_reader_source ~= nil
end

-- The reading copy of `src`, if one is open.
local function copy_of(src)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.b[b].markdown_reader_source == src then
      return b
    end
  end
end

-- Rebuild the copy `buf` from its source after the source changed. Each
-- window on the copy keeps the same text under the cursor and the same
-- distance from the top of the window, even when lines moved above it.
function M.refresh(buf)
  local src = vim.b[buf].markdown_reader_source
  if not (src and vim.api.nvim_buf_is_valid(src) and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local old = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local lines, map = copy.spaced_lines(vim.api.nvim_buf_get_lines(src, 0, -1, false))
  local views = {}
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    views[w] = vim.api.nvim_win_call(w, vim.fn.winsaveview)
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.b[buf].markdown_reader_map = map
  style.mark_words(buf, lines)
  for w, view in pairs(views) do
    local lnum = copy.relocate(old, view.lnum, lines)
    view.topline = math.max(1, view.topline + lnum - view.lnum)
    view.lnum = lnum
    vim.api.nvim_win_call(w, function()
      vim.fn.winrestview(view)
    end)
  end
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

-- The row of the other buffer in the pair (source `src`, copy `buf`) that
-- matches `row` of `from`.
local function matching(from, buf, row)
  local map = vim.b[buf].markdown_reader_map or {}
  return from == buf and copy.source_row(map, row) or (map[row] or row)
end

-- Keep the copy in step with its source: edits in another window, saves, and
-- changes on disk (an agent writing the file) all refresh it. Entering the copy
-- runs :checktime first, so a file changed on disk is reloaded into the source.
follow = function(src, buf)
  local group = vim.api.nvim_create_augroup("markdown_reader_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufReadPost", "FileChangedShellPost" }, {
    group = group,
    buffer = src,
    callback = function()
      vim.schedule(function()
        M.refresh(buf)
      end)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "CursorHold" }, {
    group = group,
    buffer = buf,
    callback = function()
      if vim.api.nvim_buf_is_valid(src) and vim.api.nvim_buf_get_name(src) ~= "" then
        vim.cmd("silent! checktime " .. src)
      end
    end,
  })
  -- Swapping a window between the two (<leader>mr, <C-p>, <C-n>) lands on
  -- the matching line and column at the same height: leaving one records
  -- where the other should show, entering the other applies it. The copy
  -- holds the source text line for line, so the column carries over as is.
  local handoff
  for _, b in ipairs { src, buf } do
    local other = b == src and buf or src
    vim.api.nvim_create_autocmd("BufLeave", {
      group = group,
      buffer = b,
      callback = function()
        local pos = vim.api.nvim_win_get_cursor(0)
        handoff = { to = other, row = matching(b, buf, pos[1]), col = pos[2], winline = vim.fn.winline() - 1 }
      end,
    })
    -- Placed once the switch has finished: the window restores the buffer's
    -- last cursor after BufEnter, and nvim-markdown's BufWinEnter loadview
    -- restores a saved view after any handler registered before it.
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      buffer = b,
      callback = function()
        local h, win = handoff, vim.api.nvim_get_current_win()
        handoff = nil
        if h and h.to == b then
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == b then
              place(win, h.row, h.winline, h.col)
            end
          end)
        end
      end,
    })
  end
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

-- Open a fresh reading copy of a buffer in the current window. The
-- copy is a listed buffer, so buffer switching (<C-p>, <C-n>) comes back to it,
-- and its window options are set for that buffer only.
-- `src` defaults to the current buffer at the cursor line; given a loaded
-- buffer instead, the copy opens at its top without visiting the source.
function M.enter(src)
  local win = vim.api.nvim_get_current_win()
  local row, col, winline = 1, 0, 0
  if not src then
    local pos = vim.api.nvim_win_get_cursor(win)
    src, row, col = vim.api.nvim_get_current_buf(), pos[1], pos[2]
    winline = vim.fn.winline() - 1
  end
  local lines, map = copy.spaced_lines(vim.api.nvim_buf_get_lines(src, 0, -1, false))

  local old = copy_of(src)
  if old then
    vim.api.nvim_buf_delete(old, { force = true })
  end

  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = false
  vim.b[buf].markdown_reader_source = src
  vim.b[buf].markdown_reader_map = map
  pcall(vim.api.nvim_buf_set_name, buf, "reading: " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(src), ":t"))

  vim.api.nvim_win_set_buf(win, buf)
  vim.bo[buf].filetype = "markdown"
  for name, value in pairs(reading_values) do
    vim.api.nvim_set_option_value(name, value, { scope = "local", win = win })
  end
  place(win, map[row] or 1, winline, col)

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "j", "gj", opts)
  vim.keymap.set("n", "k", "gk", opts)
  vim.keymap.set("n", "q", M.leave, opts)
  vim.keymap.set("n", "<leader>mr", M.toggle, opts)
  vim.keymap.set("n", "<CR>", links.follow, opts)

  style.set_highlights()
  style.mark_words(buf, lines)
  style.tune_render(buf)
  follow(src, buf)
end

-- Return from the reading copy to its source buffer at the matching line, and
-- close the copy.
function M.leave()
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local src = vim.b[buf].markdown_reader_source
  if not src then
    return
  end
  -- Switching the window hands the line, column and height over to the
  -- source (see follow); then the copy goes.
  if vim.api.nvim_buf_is_valid(src) then
    vim.api.nvim_win_set_buf(win, src)
  end
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- Swap the window between the normal view and the reading view, at the
-- matching line and screen height. The copy stays open, so swapping back is
-- instant; q closes it.
function M.toggle()
  local win, cur = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local src = vim.b[cur].markdown_reader_source
  if src then
    if vim.api.nvim_buf_is_valid(src) then
      vim.api.nvim_win_set_buf(win, src)
    end
    return
  end
  local buf = copy_of(cur)
  if not buf then
    return M.enter()
  end
  vim.api.nvim_win_set_buf(win, buf)
  for name, value in pairs(reading_values) do
    vim.api.nvim_set_option_value(name, value, { scope = "local", win = win })
  end
end

return M
