-- ~/.config/nvim/lua/user_functions/projects.lua
local M = {}

function M.add_project_from_line(current_line)
  local project_pattern = "PROJECT:%s*(%S+)"
  local project_name = current_line:match(project_pattern)

  if not project_name then
    require "notify"("No project name found on the line.", "error")
    return
  end

  local file_path = vim.fn.expand "~/projects.txt"
  local projects = {}
  local file = io.open(file_path, "r")

  if file then
    for line in file:lines() do
      projects[line] = true
    end
    file:close()
  end

  if projects[project_name] then
    require "notify"("Project already exists: " .. project_name, "info")
  else
    file = io.open(file_path, "a")
    if file then
      file:write(project_name .. "\n")
      file:close()
      require "notify"("Project added: " .. project_name, "info")
    else
      require "notify"("Failed to open the file.", "error")
    end
  end
end

-- Create a keymap to call the add_project_from_line function
vim.api.nvim_set_keymap(
  "i", -- Insert mode
  "<C-x>",
  [[<Cmd>lua require('user_functions.projects').add_project_from_line(vim.fn.getline('.'))<CR>]], -- Passes current line to the function
  { noremap = true, silent = false }
)

return M
