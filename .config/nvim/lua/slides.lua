-- Function to create the script and replace the command in the buffer
_G.create_script_from_command = function()
  -- Get the selected command from visual mode
  local bufnr = vim.api.nvim_get_current_buf()
  local start_pos = vim.api.nvim_buf_get_mark(bufnr, "<")
  local end_pos = vim.api.nvim_buf_get_mark(bufnr, ">")
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_pos[1] - 1, end_pos[1], false)
  lines[1] = lines[1]:sub(start_pos[2] + 1)
  lines[#lines] = lines[#lines]:sub(1, end_pos[2])
  local selected_command = table.concat(lines, " ")
  print("Selected command: " .. selected_command) -- Debug message
  local script_name = generate_script_name(selected_command)
  print("Script name: " .. script_name) -- Debug message

  -- Create the script and make it executable
  local script_path = vim.fn.expand("%:p:h") .. "/" .. script_name
  print("Script path: " .. script_path) -- Debug message
  if vim.loop.fs_stat(script_path) then
    print("File already exists. Aborting.")
    return
  end
  local file, err = io.open(script_path, "w")
  if not file then
    print("Error opening file: " .. err)
    return
  end
  file:write("#!/usr/bin/env bash\n" .. selected_command .. ' "$@"\n')
  file:close()
  os.execute("chmod +x " .. script_path)

 -- Replace the selected command with the script name
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", {})
  local ok, err = pcall(vim.api.nvim_buf_set_text, bufnr, start_pos[1] - 1, start_pos[2], end_pos[1] - 1, end_pos[2] - 1, { "./" .. script_name })
  if not ok then
    print("Error replacing text: " .. err)
  else
    print("Script created: " .. script_name)
  end
end

-- Create the keymap for the function
vim.api.nvim_set_keymap("v", "<leader>c", ":<C-u>lua create_script_from_command()<CR>", { silent = false })
