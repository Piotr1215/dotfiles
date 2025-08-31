-- Code Block Text Object (triple backticks)
-- Provides im/am text objects for code blocks in any file type

local M = {}

-- Helper to enter the right mode and set selection
local function setLinewiseSelection(startline, endline)
  -- Save jump to jumplist
  vim.cmd('normal! m`')
  
  -- Move to start line
  vim.api.nvim_win_set_cursor(0, { startline, 0 })
  
  -- Enter visual line mode if not already
  if vim.fn.mode() ~= "V" then 
    vim.cmd('normal! V')
  end
  
  -- Move to other end of selection
  vim.cmd('normal! o')
  vim.api.nvim_win_set_cursor(0, { endline, 0 })
end

-- Function to find and select code block
local function select_codeblock(inclusive)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local last_line = vim.api.nvim_buf_line_count(0)
  
  -- Search backward for opening ```
  local start_line = nil
  for i = cursor_line, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(0, i-1, i, false)[1]
    if line:match('^%s*```') then
      start_line = i
      break
    end
  end
  
  if not start_line then
    return false
  end
  
  -- Search forward for closing ```
  local end_line = nil
  for i = start_line + 1, last_line do
    local line = vim.api.nvim_buf_get_lines(0, i-1, i, false)[1]
    if line:match('^%s*```') then
      end_line = i
      break
    end
  end
  
  if not end_line then
    return false
  end
  
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
  vim.keymap.set('o', 'im', function()
    select_codeblock(false)
  end, { desc = 'inside code block', silent = true })
  
  vim.keymap.set('o', 'am', function()
    select_codeblock(true)
  end, { desc = 'around code block', silent = true })
  
  -- Visual mode mappings
  vim.keymap.set('x', 'im', function()
    select_codeblock(false)
  end, { desc = 'inside code block', silent = true })
    
  vim.keymap.set('x', 'am', function()
    select_codeblock(true)
  end, { desc = 'around code block', silent = true })
end

-- Auto-setup when loaded
M.setup()

return M