-- Code Block Text Object (triple backticks)
-- Provides im/am text objects for code blocks in any file type

local M = {}

-- Function to select code block (triple backticks)
-- This mimics the original markdown.lua implementation
local function select_codeblock(inclusive)
  -- Search backward for opening ```
  vim.cmd "call search('```', 'cb')"
  
  if inclusive then
    -- am - around (include backticks)
    vim.cmd "normal! Vo"
  else  
    -- im - inside (exclude backticks)
    vim.cmd "normal! j0Vo"
  end
  
  -- Search forward for closing ```
  vim.cmd "call search('```')"
  
  if not inclusive then
    -- For inside, go up one line to exclude the closing ```
    vim.cmd "normal! k"
  end
end

function M.setup()
  -- Set up the text object mappings globally
  -- These will work in any file type, not just markdown
  
  -- Operator-pending mode (for d, y, c, etc.)
  vim.keymap.set('o', 'im', function()
    select_codeblock(false)
  end, { desc = 'inside code block (triple backticks)' })
  
  vim.keymap.set('o', 'am', function()
    select_codeblock(true)
  end, { desc = 'around code block (triple backticks)' })
  
  -- Visual mode (for selecting)
  vim.keymap.set('x', 'im', function()
    select_codeblock(false)
  end, { desc = 'inside code block (triple backticks)' })
  
  vim.keymap.set('x', 'am', function()
    select_codeblock(true)
  end, { desc = 'around code block (triple backticks)' })
end

-- Auto-setup when loaded
M.setup()

return M