-- File: ~/.config/nvim/lua/user_functions/execute_function.lua

local M = {}

-- Function to get the node at the current cursor position
local function get_node_at_cursor()
  local ts_utils = require "nvim-treesitter.ts_utils"
  local node = ts_utils.get_node_at_cursor()
  return node
end

-- Function to find the function node the cursor is in
local function find_enclosing_function()
  local node = get_node_at_cursor()
  while node do
    if node:type() == "function_definition" or node:type() == "function_declaration" then
      return node
    end
    node = node:parent()
  end
  return nil
end

-- Function to extract text from a node
local function get_node_text(node)
  local start_row, start_col, end_row, end_col = node:range()
  local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)
  if #lines == 0 then
    return ""
  end
  lines[1] = string.sub(lines[1], start_col + 1)
  lines[#lines] = string.sub(lines[#lines], 1, end_col)
  return table.concat(lines, "\n")
end

-- Function to detect parameters from the function body
local function detect_parameters(function_text)
  local parameters = {}
  local max_param = 0

  for line in function_text:gmatch "[^\n]+" do
    -- Trim whitespace
    line = line:match "^%s*(.-)%s*$"
    -- Match parameter assignments
    local var_name, param_num = line:match "^local%s+(%w+)%s*=%s*['\"]?%$([%d]+)['\"]?"
    if var_name and param_num then
      param_num = tonumber(param_num)
      parameters[param_num] = var_name
      if param_num > max_param then
        max_param = param_num
      end
    end
  end

  -- Create an ordered list of parameters
  local ordered_parameters = {}
  for i = 1, max_param do
    if parameters[i] then
      table.insert(ordered_parameters, { name = parameters[i], index = i })
    end
  end

  return ordered_parameters
end

-- Function to prompt for parameter values using vim.ui.input
local function prompt_for_parameters(parameters, callback)
  local parameter_values = {}
  local index = 1

  local function prompt_next()
    if index > #parameters then
      callback(parameter_values)
      return
    end

    local param = parameters[index]
    local prompt = string.format("Enter value for '%s': ", param.name)

    vim.schedule(function()
      vim.ui.input({ prompt = prompt }, function(input)
        if input == nil then
          -- User canceled the input
          callback(nil)
          return
        end
        table.insert(parameter_values, { name = param.name, value = input })
        index = index + 1
        prompt_next()
      end)
    end)
  end

  if #parameters > 0 then
    prompt_next()
  else
    callback {}
  end
end

-- Function to send commands to the terminal
local function send_to_terminal(commands)
  -- Find or create a terminal buffer
  local term_buf = nil
  local term_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_get_option(buf, "buftype") == "terminal" then
      term_buf = buf
      term_win = win
      break
    end
  end

  if not term_buf then
    -- Open a new terminal
    vim.cmd "split | terminal"
    term_win = vim.api.nvim_get_current_win()
    term_buf = vim.api.nvim_get_current_buf()
  end

  local term_job_id = vim.b[term_buf].terminal_job_id

  -- Send commands
  for _, cmd in ipairs(commands) do
    vim.api.nvim_chan_send(term_job_id, cmd .. "\n")
  end

  -- Focus the terminal
  vim.api.nvim_set_current_win(term_win)
  vim.cmd "startinsert"
end

-- Main function to execute the function under cursor
function M.execute_function()
  -- Find the function node
  local function_node = find_enclosing_function()
  if not function_node then
    vim.notify("No function found under cursor.", vim.log.levels.ERROR)
    return
  end

  -- Get the function text
  local function_text = get_node_text(function_node)

  -- Detect parameters
  local parameters = detect_parameters(function_text)

  -- Prompt for parameters
  prompt_for_parameters(parameters, function(parameter_values)
    if not parameter_values then
      -- User canceled the input
      return
    end

    -- Prepare commands to send to terminal
    local commands = {}

    -- Send the function definition
    table.insert(commands, function_text)

    -- Export parameters
    for _, param in ipairs(parameter_values) do
      local export_cmd = string.format("export %s=%q", param.name, param.value)
      table.insert(commands, export_cmd)
    end

    -- Execute the function
    local function_name = function_text:match "function%s+([%w_]+)%s*%(" or function_text:match "([%w_]+)%s*%("
    if not function_name then
      vim.notify("Could not extract function name.", vim.log.levels.ERROR)
      return
    end

    local args = {}
    for _, param in ipairs(parameter_values) do
      table.insert(args, string.format("%q", param.value))
    end

    local exec_cmd = string.format("%s %s", function_name, table.concat(args, " "))
    table.insert(commands, exec_cmd)

    -- Send commands to terminal
    send_to_terminal(commands)
  end)
end

-- Keybinding: <leader>tf calls M.execute_function
vim.keymap.set("n", "<leader>tf", M.execute_function, { noremap = true, silent = true })

return M
