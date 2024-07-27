-- ~/.config/nvim/lua/user_functions/navigate_folds.lua
local M = {}

function M.NavigateFold(direction)
  local cmd = "normal! " .. direction
  local view = vim.fn.winsaveview()
  local lnum = view.lnum
  local new_lnum = lnum
  local open = true

  while lnum == new_lnum or open do
    vim.cmd(cmd)
    new_lnum = vim.fn.line "."
    open = vim.fn.foldclosed(new_lnum) < 0
  end

  if open then
    vim.fn.winrestview(view)
  end
end

return M
