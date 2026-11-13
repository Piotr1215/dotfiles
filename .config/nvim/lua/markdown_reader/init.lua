-- Markdown reading mode: <leader>mr swaps the current window to a reading copy
-- of the file and back. The copy is a listed scratch buffer (buffer switching
-- returns to it) with spaced list items (copy.lua), coloured headings, labels
-- and acronyms, always rendered (style.lua). <leader>mo picks a link,
-- <leader>mh picks a heading and <CR> follows the link under the cursor
-- (links.lua). It has no gutter or spell marks and is read-only, and it
-- refreshes when the source changes. q or <leader>mr returns to the source at
-- the matching line and closes the copy.
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
  local row = 1
  if not src then
    src, row = vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(win)[1]
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
  vim.api.nvim_win_set_cursor(win, { map[row] or 1, 0 })

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "j", "gj", opts)
  vim.keymap.set("n", "k", "gk", opts)
  vim.keymap.set("n", "q", M.leave, opts)
  vim.keymap.set("n", "<leader>mr", M.leave, opts)
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
  local map = vim.b[buf].markdown_reader_map or {}
  local row, back = vim.api.nvim_win_get_cursor(win)[1], 1
  for i, copy_row in ipairs(map) do
    if copy_row <= row then
      back = i
    end
  end

  if vim.api.nvim_buf_is_valid(src) then
    vim.api.nvim_win_set_buf(win, src)
    pcall(vim.api.nvim_win_set_cursor, win, { back, 0 })
  end
  vim.api.nvim_buf_delete(buf, { force = true })
end

function M.toggle()
  if M.is_reading() then
    M.leave()
  else
    M.enter()
  end
end

return M
