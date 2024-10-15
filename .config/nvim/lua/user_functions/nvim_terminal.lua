-- File: ~/.config/nvim/lua/user_functions/nvim_terminal.lua

-- Define the module table
local M = {}

-- Function to capture the visual selection accurately
function M.capture_visual_selection()
  -- Check if the current buffer is a terminal
  local buftype = vim.api.nvim_get_option_value("buftype", { buf = 0 })
  if buftype == "terminal" then
    vim.api.nvim_echo({ { "Error: Cannot send functions from a terminal buffer.", "ErrorMsg" } }, false, {})
    vim.notify("Error: Cannot send functions from a terminal buffer.", vim.log.levels.ERROR)
    return nil
  end

  -- Debug: Start capturing visual selection
  vim.api.nvim_echo({ { "Debug: Capturing visual selection...", "Type" } }, false, {})
  vim.notify("Capturing visual selection...", vim.log.levels.INFO)

  -- Get the start and end positions of the visual selection
  local start_pos = vim.fn.getpos "'<"
  local end_pos = vim.fn.getpos "'>"

  -- Validate positions
  if not start_pos or not end_pos then
    vim.api.nvim_echo({ { "Error: Unable to get visual selection positions.", "ErrorMsg" } }, false, {})
    vim.notify("Error: Unable to get visual selection positions.", vim.log.levels.ERROR)
    return nil
  end

  -- Extract text using nvim_buf_get_text
  local lines = vim.api.nvim_buf_get_text(
    0,
    start_pos[2] - 1, -- zero-based
    start_pos[3] - 1,
    end_pos[2] - 1,
    end_pos[3],
    {}
  )

  -- Check if lines are captured
  if not lines or #lines == 0 then
    vim.api.nvim_echo({ { "Error: No text captured from selection.", "ErrorMsg" } }, false, {})
    vim.notify("Error: No text captured from selection.", vim.log.levels.ERROR)
    return nil
  end

  -- Debug: Display captured lines
  for i, line in ipairs(lines) do
    vim.api.nvim_echo({ { string.format("Debug: Line %d: %s", i, line), "Type" } }, false, {})
  end

  return lines
end

-- Function to detect parameters from the selected function body
local function detect_parameters(function_body)
  vim.api.nvim_echo({ { "Debug: Detecting parameters...", "Type" } }, false, {})
  vim.notify("Detecting parameters...", vim.log.levels.INFO)

  local parameters = {}
  local max_param = 0

  -- Iterate through each line of the function body
  for _, line in ipairs(function_body) do
    -- Match patterns like: local var_name="$1" or local var_name=$1
    local var_name, param_num = line:match "local%s+(%w+)%s*=%s*[\"']?%$([%d]+)[\"']?"
    if var_name and param_num then
      param_num = tonumber(param_num)
      parameters[param_num] = var_name
      if param_num > max_param then
        max_param = param_num
      end
      vim.api.nvim_echo({
        { string.format("Debug: Detected parameter '%s' mapped to $%d", var_name, param_num), "Type" },
      }, false, {})
    end
  end

  -- Convert the parameters table to an ordered list based on parameter numbers
  local ordered_parameters = {}
  for i = 1, max_param do
    if parameters[i] then
      table.insert(ordered_parameters, { name = parameters[i], index = i })
      vim.api.nvim_echo({
        { string.format("Debug: Parameter %d: %s", i, parameters[i]), "Type" },
      }, false, {})
    end
  end

  -- Debug: Total parameters detected
  vim.api.nvim_echo({
    { string.format("Debug: Total parameters detected: %d", #ordered_parameters), "Type" },
  }, false, {})
  return ordered_parameters
end

-- Function to prompt the user for parameter values
local function prompt_for_parameter_values(parameters, callback)
  vim.api.nvim_echo({ { "Debug: Prompting for parameter values...", "Type" } }, false, {})
  vim.notify("Prompting for parameter values...", vim.log.levels.INFO)

  local parameter_values = {}
  local index = 1

  -- Recursive function to prompt for each parameter
  local function prompt_next()
    if index > #parameters then
      -- All parameters have been collected, proceed to callback
      vim.api.nvim_echo({ { "Debug: All parameter values collected.", "Type" } }, false, {})
      vim.notify("All parameter values collected.", vim.log.levels.INFO)
      callback(parameter_values)
      return
    end

    local param = parameters[index]
    local prompt = string.format("Enter value for '%s': ", param.name)

    -- Use vim.ui.input for asynchronous input
    vim.ui.input({ prompt = prompt }, function(input)
      if input == nil then
        -- If user cancels input, set value as empty string
        table.insert(parameter_values, { name = param.name, value = "" })
        vim.api.nvim_echo({
          {
            string.format("Debug: User canceled input for parameter '%s'. Setting to empty string.", param.name),
            "Type",
          },
        }, false, {})
        vim.notify(string.format("Canceled input for '%s'. Setting to empty string.", param.name), vim.log.levels.WARN)
      else
        table.insert(parameter_values, { name = param.name, value = input })
        vim.api.nvim_echo({
          { string.format("Debug: Received input for '%s': '%s'", param.name, input), "Type" },
        }, false, {})
        vim.notify(string.format("Received input for '%s': '%s'", param.name, input), vim.log.levels.INFO)
      end
      index = index + 1
      prompt_next()
    end)
  end

  prompt_next()
end

-- Function to export parameter values to the terminal
local function export_parameters(term_job_id, parameter_values)
  vim.api.nvim_echo({ { "Debug: Exporting parameters to terminal...", "Type" } }, false, {})
  vim.notify("Exporting parameters to terminal...", vim.log.levels.INFO)

  for _, param in ipairs(parameter_values) do
    -- Construct the export command
    local export_cmd = string.format('export %s="%s"', param.name, param.value)

    -- Debug: Display export command and its type
    vim.api.nvim_echo({
      { string.format("Debug: Export command type: %s", type(export_cmd)), "Type" },
      { string.format("Debug: Export command: %s", export_cmd), "Type" },
    }, false, {})

    -- Type check before sending
    if type(export_cmd) == "string" then
      vim.api.nvim_chan_send(term_job_id, export_cmd .. "\n")
      vim.api.nvim_echo({
        { string.format("Debug: Sent to terminal: %s", export_cmd), "Type" },
      }, false, {})
      vim.notify(string.format('Exported %s="%s"', param.name, param.value), vim.log.levels.INFO)
    else
      vim.api.nvim_echo({
        { string.format("Debug: export_cmd is not a string. Type: %s", type(export_cmd)), "Error" },
      }, false, {})
      vim.notify("Error: export_cmd is not a string.", vim.log.levels.ERROR)
    end
  end
end

-- Function to prepare and execute the function in the terminal
local function prepare_and_execute_function(term_job_id, function_name, parameter_values)
  vim.api.nvim_echo({ { "Debug: Preparing function execution...", "Type" } }, false, {})
  vim.notify("Preparing function execution...", vim.log.levels.INFO)

  -- Collect parameter values in the correct order
  local args = {}
  for _, param in ipairs(parameter_values) do
    if type(param.value) == "string" then
      table.insert(args, param.value)
    else
      vim.api.nvim_echo({
        {
          string.format(
            "Debug: Parameter value is not a string: %s (type: %s)",
            tostring(param.value),
            type(param.value)
          ),
          "Error",
        },
      }, false, {})
      vim.notify("Error: Parameter value is not a string.", vim.log.levels.ERROR)
      return
    end
  end

  -- Construct the function execution command with quoted arguments
  local exec_cmd = string.format('%s "%s"', function_name, table.concat(args, '" "'))

  -- Debug: Display the function call and its type
  vim.api.nvim_echo({
    { string.format("Debug: Function call type: %s", type(exec_cmd)), "Type" },
    { string.format("Debug: Function call to send: %s", exec_cmd), "Type" },
  }, false, {})
  vim.notify(string.format("Function call prepared: %s", exec_cmd), vim.log.levels.INFO)

  -- Type check before sending
  if type(exec_cmd) == "string" then
    vim.api.nvim_chan_send(term_job_id, exec_cmd .. "\n")
    vim.api.nvim_echo({
      { string.format("Debug: Function call sent to terminal: %s", exec_cmd), "Type" },
    }, false, {})
  else
    vim.api.nvim_echo({
      { string.format("Debug: exec_cmd is not a string. Type: %s", type(exec_cmd)), "Error" },
    }, false, {})
    vim.notify("Error: exec_cmd is not a string.", vim.log.levels.ERROR)
  end
end

-- Helper function to find or open a terminal buffer without replacing the original buffer
local function get_or_open_terminal(callback)
  vim.api.nvim_echo({ { "Debug: Searching for existing terminal buffers...", "Type" } }, false, {})
  vim.notify("Searching for existing terminal buffers...", vim.log.levels.INFO)

  -- Iterate through all buffers to find an existing terminal
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
    if buftype == "terminal" then
      local term_job_id = vim.b[buf].terminal_job_id
      if term_job_id and type(term_job_id) == "number" then
        vim.api.nvim_echo({
          { string.format("Debug: Found existing terminal buffer: %d with job ID: %d", buf, term_job_id), "Type" },
        }, false, {})
        vim.notify(string.format("Found existing terminal buffer: %d", buf), vim.log.levels.INFO)
        callback(buf, term_job_id)
        return
      else
        vim.api.nvim_echo({
          {
            string.format("Debug: Terminal buffer %d found but job ID is invalid: %s", buf, tostring(term_job_id)),
            "Warn",
          },
        }, false, {})
        vim.notify(string.format("Terminal buffer %d found but job ID is invalid.", buf), vim.log.levels.WARN)
      end
    end
  end

  -- If no terminal buffer is found, open a new one in a horizontal split without focusing it
  vim.api.nvim_echo({ { "Debug: No existing terminal buffer found. Opening a new one...", "Type" } }, false, {})
  vim.notify("No existing terminal buffer found. Opening a new terminal...", vim.log.levels.INFO)

  -- Save the current window
  local original_win = vim.api.nvim_get_current_win()

  -- Open a new horizontal split with a terminal
  vim.cmd "split | terminal"
  local term_buf = vim.api.nvim_get_current_buf()
  local term_job_id = vim.b[term_buf].terminal_job_id

  -- Wait briefly to ensure the terminal buffer is initialized
  vim.defer_fn(function()
    local buftype = vim.api.nvim_get_option_value("buftype", { buf = term_buf })
    if buftype ~= "terminal" then
      vim.api.nvim_echo({
        { "Debug: Opened buffer is not a terminal.", "Error" },
      }, false, {})
      vim.notify("Error: Opened buffer is not a terminal.", vim.log.levels.ERROR)
      return
    end

    term_job_id = vim.b[term_buf].terminal_job_id
    if term_job_id and type(term_job_id) == "number" then
      vim.api.nvim_echo({
        { string.format("Debug: Terminal buffer %d initialized with job ID: %d", term_buf, term_job_id), "Type" },
      }, false, {})
      vim.notify(string.format("Terminal buffer %d initialized.", term_buf), vim.log.levels.INFO)
      callback(term_buf, term_job_id)
    else
      vim.api.nvim_echo({
        { "Debug: Failed to initialize terminal buffer.", "Error" },
      }, false, {})
      vim.notify("Error: Failed to initialize terminal buffer.", vim.log.levels.ERROR)
    end

    -- Restore focus to the original window
    vim.api.nvim_set_current_win(original_win)
  end, 400) -- Increased delay to 400 milliseconds
end

-- Main function exposed to keybinding, send selected function to terminal
function M.sendToTerminal()
  vim.api.nvim_echo({ { "Debug: sendToTerminal triggered.", "Type" } }, false, {})
  vim.notify("Sending function to terminal...", vim.log.levels.INFO)

  -- Save the original window and buffer
  local original_win = vim.api.nvim_get_current_win()
  local original_buf = vim.api.nvim_get_current_buf()

  -- Capture the visual selection
  local selected_lines = M.capture_visual_selection()
  if not selected_lines then
    -- Error messages are already handled in capture_visual_selection
    return
  end

  -- Detect parameters
  local parameters = detect_parameters(selected_lines)

  -- Extract the function name from the first line
  -- Enhanced regex to handle various function declaration styles
  local function_name = selected_lines[1]:match "^%s*function%s+([%w_]+)%s*%("
  if not function_name then
    -- Attempt to match alternative function definitions (e.g., without 'function' keyword)
    function_name = selected_lines[1]:match "^%s*([%w_]+)%s*%("
    if not function_name then
      vim.api.nvim_echo({
        { "Debug: Could not extract function name.", "ErrorMsg" },
      }, false, {})
      vim.notify("Error: Could not extract function name.", vim.log.levels.ERROR)
      return
    end
  end

  vim.api.nvim_echo({
    { string.format("Debug: Function name detected: %s", function_name), "Type" },
  }, false, {})
  vim.notify(string.format("Function name detected: %s", function_name), vim.log.levels.INFO)

  -- Get or open the terminal buffer
  get_or_open_terminal(function(buf, term_job_id)
    if not term_job_id then
      vim.api.nvim_echo({
        { "Debug: Failed to get terminal job ID.", "ErrorMsg" },
      }, false, {})
      vim.notify("Error: Failed to get terminal job ID.", vim.log.levels.ERROR)
      return
    end

    -- Send the function definition to the terminal
    for _, line in ipairs(selected_lines) do
      -- Type check: Ensure each line is a string
      if type(line) == "string" then
        vim.api.nvim_chan_send(term_job_id, line .. "\n")
        vim.api.nvim_echo({
          { string.format("Debug: Sent to terminal: %s", line), "Type" },
        }, false, {})
        vim.notify(string.format("Sent to terminal: %s", line), vim.log.levels.INFO)
      else
        vim.api.nvim_echo({
          { string.format("Debug: Unexpected type for line: %s (type: %s)", tostring(line), type(line)), "ErrorMsg" },
        }, false, {})
        vim.notify(
          string.format("Error: Unexpected type for line: %s (type: %s)", tostring(line), type(line)),
          vim.log.levels.ERROR
        )
      end
    end

    -- Send Enter to register the function
    vim.api.nvim_chan_send(term_job_id, "\n")
    vim.api.nvim_echo({
      { "Debug: Function definition sent to terminal.", "Type" },
    }, false, {})
    vim.notify("Function definition sent to terminal.", vim.log.levels.INFO)

    -- If there are parameters, prompt for their values
    if #parameters > 0 then
      -- Prompt for parameter values
      prompt_for_parameter_values(parameters, function(parameter_values)
        -- Export parameters
        export_parameters(term_job_id, parameter_values)

        -- Prepare the function call
        prepare_and_execute_function(term_job_id, function_name, parameter_values)

        -- Restore focus to the original window and buffer
        vim.api.nvim_set_current_win(original_win)
        vim.api.nvim_set_current_buf(original_buf)
        vim.cmd "startinsert"

        -- Notify the user to press Enter to execute the function
        vim.notify("Function call prepared in terminal. Press Enter to execute.", vim.log.levels.INFO)
      end)
    else
      -- No parameters, just execute the function
      prepare_and_execute_function(term_job_id, function_name, {})
      vim.api.nvim_echo({
        { "Debug: Function executed successfully in terminal.", "Type" },
      }, false, {})
      vim.notify("Function executed successfully in terminal.", vim.log.levels.INFO)

      -- Restore focus to the original window and buffer
      vim.api.nvim_set_current_win(original_win)
      vim.api.nvim_set_current_buf(original_buf)
      vim.cmd "startinsert"

      -- Notify the user to press Enter to execute the function
      vim.notify("Function call prepared in terminal. Press Enter to execute.", vim.log.levels.INFO)
    end
  end)
end

-- Keybinding: <leader>tt calls M.sendToTerminal
vim.keymap.set("v", "<leader>tt", M.sendToTerminal, { noremap = true, silent = true })

-- Return the module
return M
