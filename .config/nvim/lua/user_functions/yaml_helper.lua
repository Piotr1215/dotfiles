local M = {}

function M.paste_and_adjust_yaml()
  -- Get the current column and line
  local start_col = vim.fn.col "."
  local current_line = vim.fn.line "."

  -- Create a new line above and move to it, maintaining the column
  vim.cmd "normal! O"
  vim.fn.cursor(current_line, start_col)

  -- Paste the content
  vim.cmd 'normal! "+p'

  -- Mark the end of the pasted text
  vim.cmd "normal! `]ma"

  -- Go to the start of the pasted text and mark it
  vim.cmd "normal! '[mb"

  -- Get the line numbers of the pasted block
  local start_line = vim.fn.line "'b"
  local end_line = vim.fn.line "'a"

  -- Get the indentation of the first line of the pasted content
  local first_line_content = vim.fn.getline(start_line)
  local first_line_indent = first_line_content:match("^%s*"):len()

  -- Calculate the indentation difference
  local indent_diff = start_col - first_line_indent - 1

  -- Adjust each line's indentation
  for line = start_line, end_line do
    local content = vim.fn.getline(line)
    local current_indent = content:match("^%s*"):len()
    local new_indent = current_indent + indent_diff
    local new_content = string.rep(" ", new_indent) .. content:gsub("^%s*", "")
    vim.fn.setline(line, new_content)
  end

  -- Move cursor back to the original position
  vim.fn.cursor(current_line + 1, start_col)
end

vim.keymap.set("n", "<leader>py", M.paste_and_adjust_yaml, { remap = true, silent = false })

return M
