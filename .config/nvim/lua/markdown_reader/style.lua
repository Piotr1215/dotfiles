-- Reading view look: heading and keyword colours, gaps between list items,
-- and render-markdown tuned for reading (cursor line rendered, bars around
-- headings).
local M = {}

-- Heading, bullet and emphasis colours for the reading view, linked to the
-- colourscheme's own groups so they follow theme changes.
function M.set_highlights()
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
function M.mark_words(buf, lines)
  local label_fg = vim.api.nvim_get_hl(0, { name = "Function", link = false }).fg
  local term_fg = vim.api.nvim_get_hl(0, { name = "Type", link = false }).fg
  vim.api.nvim_set_hl(0, "MarkdownReaderLabel", { fg = label_fg, bold = true })
  vim.api.nvim_set_hl(0, "MarkdownReaderTerm", { fg = term_fg })
  local function mark(row, from, to, group)
    vim.api.nvim_buf_set_extmark(buf, ns, row, from, { end_col = to, hl_group = group, priority = 200 })
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
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

local gap_ns = vim.api.nvim_create_namespace "markdown_reader_gaps"

-- Draw an empty virtual line below each row in `gaps` (see paragraphs.lua).
function M.mark_gaps(buf, gaps)
  vim.api.nvim_buf_clear_namespace(buf, gap_ns, 0, -1)
  for row in pairs(gaps) do
    vim.api.nvim_buf_set_extmark(buf, gap_ns, row - 1, 0, { virt_lines = { { { "", "" } } } })
  end
end

-- Remove the reading marks (words and gaps) from `buf`.
function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, gap_ns, 0, -1)
end

-- Per-buffer render-markdown tweaks: render the cursor line too, and draw bars
-- above and below headings. Touches the plugin's buffer state, so pcall.
function M.tune_render(buf)
  pcall(function()
    local config = require("render-markdown.state").get(buf)
    config.anti_conceal.enabled = false
    config.heading.border = true
    require("render-markdown").buf_enable()
  end)
end

return M
