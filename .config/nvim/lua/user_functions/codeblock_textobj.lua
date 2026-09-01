-- Code Block Text Object (triple backticks)
-- Provides im/am text objects for code blocks in any file type

local M = {}

-- Helper to enter the right mode and set selection
local function setLinewiseSelection(startline, endline)
  -- Save jump to jumplist
  vim.cmd "normal! m`"

  -- Move to start line
  vim.api.nvim_win_set_cursor(0, { startline, 0 })

  -- Enter visual line mode if not already
  if vim.fn.mode() ~= "V" then
    vim.cmd "normal! V"
  end

  -- Move to other end of selection
  vim.cmd "normal! o"
  vim.api.nvim_win_set_cursor(0, { endline, 0 })
end

-- Collect every fenced block in the buffer as { open_line, close_line } pairs.
-- Scanning from the top is what tells an opening fence from a closing one, so
-- the cursor sitting between two blocks cannot mistake a closing ``` for a start.
local function collect_blocks()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local blocks = {}
  local open_line = nil

  for i, line in ipairs(lines) do
    if line:match "^%s*```" then
      if open_line then
        table.insert(blocks, { open_line, i })
        open_line = nil
      else
        open_line = i
      end
    end
  end

  return blocks
end

-- The block under the cursor, else the next one below it, else the last one above it
local function find_block(cursor_line)
  local previous = nil

  for _, block in ipairs(collect_blocks()) do
    if cursor_line <= block[2] then
      -- Covers both the block containing the cursor and the first one below it
      return block
    end
    previous = block
  end

  return previous
end

-- Function to find and select code block
local function select_codeblock(inclusive)
  local block = find_block(vim.api.nvim_win_get_cursor(0)[1])

  if not block then
    return false
  end

  local start_line, end_line = block[1], block[2]

  -- Set the selection
  if inclusive then
    -- am - around (include backticks)
    setLinewiseSelection(start_line, end_line)
  else
    -- im - inside (exclude backticks)
    if start_line + 1 <= end_line - 1 then
      setLinewiseSelection(start_line + 1, end_line - 1)
    else
      return false -- empty code block
    end
  end

  return true
end

function M.setup()
  -- Operator-pending mode mappings
  vim.keymap.set("o", "im", function()
    select_codeblock(false)
  end, { desc = "inside code block", silent = true })

  vim.keymap.set("o", "am", function()
    select_codeblock(true)
  end, { desc = "around code block", silent = true })

  -- Visual mode mappings
  vim.keymap.set("x", "im", function()
    select_codeblock(false)
  end, { desc = "inside code block", silent = true })

  vim.keymap.set("x", "am", function()
    select_codeblock(true)
  end, { desc = "around code block", silent = true })
end

-- Auto-setup when loaded
M.setup()

return M
