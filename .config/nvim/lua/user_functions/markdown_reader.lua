-- Markdown reading mode: <leader>mr swaps the current window to a reading copy
-- of the file and back. The copy is a scratch buffer with a blank line between
-- list items, so dense lists breathe; it is always fully rendered (no raw text
-- under the cursor), coloured, with a slim left margin instead of the gutter,
-- no spell marks, and read-only. q or <leader>mr returns to the source buffer at
-- the matching line, with the editing view as it was.
local M = {}

local win_opts =
  { "number", "relativenumber", "signcolumn", "foldcolumn", "cursorline", "spell", "colorcolumn", "list" }
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

-- Heading, bullet and emphasis colours for the reading view, linked to the
-- colourscheme's own groups so they follow theme changes.
local function set_highlights()
  local links = {
    RenderMarkdownH1 = "Function",
    RenderMarkdownH2 = "Keyword",
    RenderMarkdownH3 = "String",
    RenderMarkdownH4 = "Type",
    RenderMarkdownH5 = "Constant",
    RenderMarkdownH6 = "Special",
    RenderMarkdownBullet = "Keyword",
  }
  for group, target in pairs(links) do
    local fg = vim.api.nvim_get_hl(0, { name = target, link = false }).fg
    vim.api.nvim_set_hl(0, group, { fg = fg, bold = true })
  end
  for level = 1, 6 do
    vim.api.nvim_set_hl(0, "@markup.heading." .. level .. ".markdown", { link = "RenderMarkdownH" .. level })
  end
  vim.api.nvim_set_hl(0, "@markup.strong", { bold = true, link = "Identifier" })
end

local ns = vim.api.nvim_create_namespace "markdown_reader"

-- Colour the words a reader scans for: a lead-in label ending in a colon at the
-- start of a list item or paragraph ("Problem the viewer recognizes:"), and
-- acronyms such as MCP, API or CI/CD. Fenced code is left alone.
local function mark_words(buf, lines)
  local label_fg = vim.api.nvim_get_hl(0, { name = "Function", link = false }).fg
  local term_fg = vim.api.nvim_get_hl(0, { name = "Type", link = false }).fg
  vim.api.nvim_set_hl(0, "MarkdownReaderLabel", { fg = label_fg, bold = true })
  vim.api.nvim_set_hl(0, "MarkdownReaderTerm", { fg = term_fg })
  local function mark(row, from, to, group)
    vim.api.nvim_buf_set_extmark(buf, ns, row, from, { end_col = to, hl_group = group, priority = 200 })
  end
  local in_fence = false
  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match "^%s*```" or line:match "^%s*~~~" then
      in_fence = not in_fence
    elseif not in_fence and not line:match "^#" then
      local prefix = line:match "^%s*[-*+]%s+" or line:match "^%s*%d+[.)]%s+" or ""
      local label = line:sub(#prefix + 1):match "^([%a][^:`%[]-:)%s"
      local _, words = (label or ""):gsub("%S+", "")
      if label and words <= 6 and not label:find "," then
        mark(row, #prefix, #prefix + #label, "MarkdownReaderLabel")
      end
      local pos = 1
      while true do
        local s, e = line:find("%f[%w]%u[%u/]*%u%f[%W]", pos)
        if not s then
          break
        end
        mark(row, s - 1, e, "MarkdownReaderTerm")
        pos = e + 1
      end
    end
  end
end

local function is_list_item(line)
  return line:match "^%s*[-*+]%s" or line:match "^%s*%d+[.)]%s"
end

-- Build the reading copy of `lines`. Returns the new lines and a map from each
-- source line number to its line number in the copy.
function M.spaced_lines(lines)
  local out, map, in_fence = {}, {}, false
  for i, line in ipairs(lines) do
    if line:match "^%s*```" or line:match "^%s*~~~" then
      in_fence = not in_fence
    end
    out[#out + 1] = line
    map[i] = #out
    local next_line = lines[i + 1]
    if not in_fence and next_line and is_list_item(line) and is_list_item(next_line) then
      out[#out + 1] = ""
    end
  end
  return out, map
end

-- Per-buffer render-markdown tweaks: render the cursor line too, and draw bars
-- above and below headings. Touches the plugin's buffer state, so pcall.
local function tune_render(buf)
  pcall(function()
    local config = require("render-markdown.state").get(buf)
    config.anti_conceal.enabled = false
    config.heading.border = true
    require("render-markdown").buf_enable()
  end)
end

-- Whether the current buffer is a reading copy.
function M.is_reading(buf)
  return vim.b[buf or 0].markdown_reader_source ~= nil
end

-- Open the reading copy of the current buffer in the current window.
function M.enter()
  local src, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local lines, map = M.spaced_lines(vim.api.nvim_buf_get_lines(src, 0, -1, false))
  local row = vim.api.nvim_win_get_cursor(win)[1]

  local saved = {}
  for _, name in ipairs(win_opts) do
    saved[name] = vim.wo[win][name]
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.b[buf].markdown_reader_source = src
  vim.b[buf].markdown_reader_saved = saved
  vim.b[buf].markdown_reader_map = map
  pcall(vim.api.nvim_buf_set_name, buf, "reading: " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(src), ":t"))

  vim.api.nvim_win_set_buf(win, buf)
  vim.bo[buf].filetype = "markdown"
  for name, value in pairs(reading_values) do
    vim.wo[win][name] = value
  end
  vim.api.nvim_win_set_cursor(win, { map[row] or 1, 0 })

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "j", "gj", opts)
  vim.keymap.set("n", "k", "gk", opts)
  vim.keymap.set("n", "q", M.leave, opts)
  vim.keymap.set("n", "<leader>mr", M.leave, opts)

  set_highlights()
  mark_words(buf, lines)
  tune_render(buf)
end

-- Return from the reading copy to its source buffer at the matching line.
function M.leave()
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local src = vim.b[buf].markdown_reader_source
  if not src then
    return
  end
  local saved, map = vim.b[buf].markdown_reader_saved or {}, vim.b[buf].markdown_reader_map or {}
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
  for name, value in pairs(saved) do
    vim.wo[win][name] = value
  end
end

function M.toggle()
  if M.is_reading() then
    M.leave()
  else
    M.enter()
  end
end

return M
