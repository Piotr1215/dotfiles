-- Search match text object for mini.ai
-- Allows operations on the last search pattern (from / or ?)
-- Usage: da/ (delete around search), ci/ (change inner search), ya/ (yank around search)

local M = {}

-- Main function for the search text object
-- @param ai_type string: 'a' for around, 'i' for inner
-- @param _ unused parameter
-- @param opts table: options from mini.ai (includes n_lines, reference_region, etc.)
-- @return table|nil: array of regions or nil if no matches
function M.search_textobject(ai_type, _, opts)
  -- Get the last search pattern from the search register
  local pattern = vim.fn.getreg('/')
  if pattern == '' or pattern == nil then 
    return nil 
  end
  
  -- Find all matches in the visible area
  local regions = {}
  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local current_line = cursor[1]
  
  -- Search within n_lines from cursor (respecting mini.ai search area)
  -- Default to 50 lines if not specified
  local n_lines = opts.n_lines or 50
  local start_line = math.max(1, current_line - n_lines)
  local end_line = math.min(vim.api.nvim_buf_line_count(0), current_line + n_lines)
  
  -- Save current position to restore later
  local saved_pos = vim.fn.getpos('.')
  
  -- Move to start of search area
  vim.fn.cursor(start_line, 1)
  
  -- Find all matches in the search area
  while true do
    -- Find next match using vim's native search
    -- 'W' flag means don't wrap around
    local match_start = vim.fn.searchpos(pattern, 'W', end_line)
    if match_start[1] == 0 then break end
    
    -- Move cursor to the match start
    vim.fn.cursor(match_start[1], match_start[2])
    
    -- Find end of match by searching with 'e' flag (end of match)
    -- 'c' flag means accept match at cursor position
    local match_end = vim.fn.searchpos(pattern, 'ceW', end_line)
    if match_end[1] == 0 then break end
    
    -- Add region for this match
    -- mini.ai expects 1-based line and column numbers
    table.insert(regions, {
      from = { line = match_start[1], col = match_start[2] },
      to = { line = match_end[1], col = match_end[2] },
    })
    
    -- Move cursor past this match for next search
    vim.fn.cursor(match_end[1], match_end[2] + 1)
  end
  
  -- Restore original cursor position
  vim.fn.setpos('.', saved_pos)
  
  if #regions == 0 then 
    return nil 
  end
  
  -- Return all regions, mini.ai will pick the best one based on search_method
  -- (cover, cover_or_next, cover_or_prev, cover_or_nearest, next, prev, nearest)
  return regions
end

return M