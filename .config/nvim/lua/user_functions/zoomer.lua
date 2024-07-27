local M = {}

M.zoomed = false

function M.zoom()
  if M.zoomed == false then
    vim.api.nvim_command "wincmd |"
    vim.api.nvim_command "wincmd _"
    M.zoomed = true
  else
    vim.api.nvim_command "wincmd ="
    M.zoomed = false
  end
end

vim.keymap.set("n", "<leader>zom", M.zoom, { noremap = true, silent = true })

return M
