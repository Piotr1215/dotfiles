-- lua/nvim-typing-simulation/init.lua

local M = {}

local is_typing = false

-- Function to expand the home directory
function M.expand_home(path)
  if path:sub(1, 1) == "~" then
    local home = os.getenv "HOME"
    if home then
      return home .. path:sub(2)
    end
  end
  return path
end

-- Function to read the entire content of a file
function M.read_file(file_path)
  file_path = M.expand_home(file_path)
  local file = io.open(file_path, "r")
  if not file then
    print("Error opening file: " .. file_path)
    return nil
  end
  local content = file:read "*all"
  file:close()
  return content
end

-- Function to set the filetype based on the file extension or name
function M.set_filetype(file_path)
  local extension = vim.fn.fnamemodify(file_path, ":e")
  local filename = vim.fn.fnamemodify(file_path, ":t")
  local filetype = extension

  -- Special cases
  if filename:lower() == "dockerfile" then
    filetype = "dockerfile"
  elseif extension == "md" then
    filetype = "markdown"
  -- Add more special cases here if needed
  elseif extension == "" then
    filetype = ""
  end

  if filetype ~= "" then
    vim.api.nvim_buf_set_option(0, "filetype", filetype)
    print("Filetype set to: " .. filetype)
  else
    print "No filetype set"
  end
end

-- Function to simulate typing
function M.simulate_typing(text, speed)
  local timer = vim.loop.new_timer()
  local i = 1
  is_typing = true
  timer:start(
    0,
    speed,
    vim.schedule_wrap(function()
      if not is_typing then
        timer:stop()
        timer:close()
        return
      end
      if i <= #text then
        local char = text:sub(i, i)
        if char == "\n" then
          vim.api.nvim_command "normal! o"
        else
          vim.api.nvim_put({ char }, "c", true, true)
        end
        i = i + 1
      else
        timer:stop()
        timer:close()
      end
    end)
  )
end

-- Function to simulate typing with pauses after each line or paragraph
function M.simulate_typing_with_pauses(text, pause_at, speed)
  local lines = vim.split(text, "\n", { plain = true })
  local i = 1
  local j = 1
  is_typing = true
  local in_paragraph = false

  local function type_line(line)
    local timer = vim.loop.new_timer()
    timer:start(
      0,
      speed,
      vim.schedule_wrap(function()
        if not is_typing then
          timer:stop()
          timer:close()
          return
        end
        if j <= #line then
          vim.api.nvim_put({ line:sub(j, j) }, "c", true, true)
          j = j + 1
        else
          timer:stop()
          timer:close()
          if i < #lines then
            vim.api.nvim_command "normal! o"
            local should_pause = false
            if pause_at == "line" then
              should_pause = true
            elseif pause_at == "paragraph" then
              if line == "" then
                in_paragraph = false
                should_pause = true
              elseif not in_paragraph then
                in_paragraph = true
                should_pause = true
              end
            end
            if should_pause then
              vim.cmd "echo 'Press Enter to continue...'"
              vim.fn.getchar()
              vim.cmd "echo ''"
            end
            i = i + 1
            j = 1
            type_line(lines[i])
          end
        end
      end)
    )
  end

  type_line(lines[i])
end

-- Function to start typing simulation from a file
function M.start_typing_simulation_from_file(file_path, speed, pause_at)
  local text = M.read_file(file_path)
  if text then
    M.set_filetype(file_path)
    if pause_at then
      M.simulate_typing_with_pauses(text, pause_at, speed or 50)
    else
      M.simulate_typing(text, speed or 50)
    end
  else
    print("Failed to read file: " .. file_path)
  end
end

-- Function to stop typing simulation
function M.stop_typing_simulation()
  is_typing = false
end

-- Autocompletion function for file paths and speed
function M.complete_simulate_typing(arg_lead, cmd_line, cursor_pos)
  local args = vim.split(cmd_line, " ")
  if #args == 2 then
    return vim.fn.getcompletion(arg_lead, "file")
  elseif #args == 3 then
    return { "10", "20", "30", "40", "50", "60", "70", "80", "90", "100" }
  elseif #args == 4 then
    return { "line", "paragraph" }
  end
end

-- Define the custom command to start typing simulation
vim.api.nvim_create_user_command("SimulateTyping", function(opts)
  local args = vim.split(opts.args, " ")
  local file_path = args[1]
  local speed = tonumber(args[2]) or 50
  M.start_typing_simulation_from_file(file_path, speed)
end, { nargs = "+", complete = M.complete_simulate_typing })

-- Define the custom command to start typing simulation with pauses after each line
vim.api.nvim_create_user_command("SimulateTypingWithPauses", function(opts)
  local args = vim.split(opts.args, " ")
  local file_path = args[1]
  local speed = tonumber(args[2]) or 50
  local pause_at = args[3] or "line"
  M.start_typing_simulation_from_file(file_path, speed, pause_at)
end, { nargs = "+", complete = M.complete_simulate_typing })

-- Define the custom command to start typing simulation with pauses after each paragraph
vim.api.nvim_create_user_command("SimulateTypingWithParagraphPauses", function(opts)
  local args = vim.split(opts.args, " ")
  local file_path = args[1]
  local speed = tonumber(args[2]) or 50
  M.start_typing_simulation_from_file(file_path, speed, "paragraph")
end, { nargs = "+", complete = M.complete_simulate_typing })

-- Define the command to stop typing
vim.api.nvim_create_user_command("StopTyping", function()
  M.stop_typing_simulation()
end, {})

return M
