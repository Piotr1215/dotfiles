local M = {}
M.zoomed = false

function M.toggle_zoom()
  if M.zoomed then
    vim.api.nvim_command "wincmd ="
    M.zoomed = false
  else
    vim.api.nvim_command "wincmd _"
    vim.api.nvim_command "wincmd |"
    M.zoomed = true
  end
end

vim.keymap.set("n", "<leader>zw", M.toggle_zoom, { noremap = true, silent = true })

return M
