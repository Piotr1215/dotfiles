-- ~/.config/nvim/lua/user_functions/horizontal_scroll.lua
local M = {}
local horizontal_scroll_enabled = false

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

-- Register the command to toggle horizontal scrolling
vim.api.nvim_create_user_command("HorizontalScrollMode", function()
  M.ToggleHorizontalScroll()
end, {})

return M
