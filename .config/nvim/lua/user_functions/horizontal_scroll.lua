local M = {}
local horizontal_scroll_enabled = false
local vertical_scroll_enabled = false

function M.ToggleHorizontalScroll()
  if horizontal_scroll_enabled then
    -- Disable horizontal scrolling
    vim.wo.wrap = true
    vim.opt.sidescrolloff = 0
    vim.opt.sidescroll = 0
    horizontal_scroll_enabled = false
    print "Horizontal scroll disabled"
  else
    -- Enable horizontal scrolling
    vim.wo.wrap = false
    vim.opt.sidescrolloff = 5
    vim.opt.sidescroll = 1
    horizontal_scroll_enabled = true
    print "Horizontal scroll enabled"
  end
end

function M.ToggleVerticalScroll()
  if vertical_scroll_enabled then
    -- Disable vertical scrolling
    vim.wo.scrolloff = 0
    vim.wo.scroll = vim.api.nvim_win_get_height(0)
    vertical_scroll_enabled = false
    print "Vertical scroll disabled"
  else
    -- Enable vertical scrolling (freeze at 50% of screen height)
    local window_height = vim.api.nvim_win_get_height(0)
    local scroll_offset = math.floor(window_height * 0.5)
    vim.wo.scrolloff = scroll_offset
    vim.wo.scroll = 1
    vertical_scroll_enabled = true

    -- Set up an autocommand to maintain scroll position
    vim.cmd [[
      augroup VerticalScrollLock
        autocmd!
        autocmd VimResized,WinScrolled * lua vim.wo.scrolloff = math.floor(vim.api.nvim_win_get_height(0) * 0.5)
      augroup END
    ]]

    print "Vertical scroll enabled (frozen at 50% of screen height)"
  end
end

-- Register the command to toggle horizontal scrolling
vim.api.nvim_create_user_command("HorizontalScrollMode", function()
  M.ToggleHorizontalScroll()
end, {})

-- Register the command to toggle vertical scrolling
vim.api.nvim_create_user_command("VerticalScrollMode", function()
  M.ToggleVerticalScroll()
end, {})

return M
