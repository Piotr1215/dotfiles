-- ~/.config/nvim/lua/user_functions/annotate_text.lua
local M = {}

function M.AnnotateText()
  -- Get the start and end positions of the selected text
  local s_line, s_col = unpack(vim.api.nvim_buf_get_mark(0, "<"))
  local e_line, e_col = unpack(vim.api.nvim_buf_get_mark(0, ">"))

  -- Ensure s_line is the first and e_line is the last line of the selection
  if s_line > e_line or (s_line == e_line and s_col > e_col) then
    s_line, e_line = e_line, s_line
    s_col, e_col = e_col, s_col
  end

  -- Get the lines within the selection
  local lines = vim.api.nvim_buf_get_lines(0, s_line - 1, e_line, false)
  local selected_text = lines[1]:sub(s_col, e_col)

  -- Create the |--| line directly below the selected text
  local dash_line = string.rep(" ", s_col - 1) .. "|" .. string.rep("-", #selected_text) .. "|"
  local pipe_line = string.rep(" ", s_col - 1) .. "|"

  -- Find the correct position to insert new vertical bars
  local insert_pos = s_line
  while vim.fn.getline(insert_pos):match "^%s*|" do
    insert_pos = insert_pos + 1
  end

  -- Ensure |--| line is always added directly below the selected text
  vim.api.nvim_buf_set_lines(0, insert_pos, insert_pos, false, { dash_line })

  -- Add new | lines below the |--| line
  local i = insert_pos + 1
  while vim.fn.getline(i):match "^%s*|" do
    i = i + 1
  end
  vim.api.nvim_buf_set_lines(0, i, i, false, { pipe_line })
end

vim.keymap.set("v", "<leader>an", M.AnnotateText, { noremap = true, silent = true })

return M
