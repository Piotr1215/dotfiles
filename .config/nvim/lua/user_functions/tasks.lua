-- ~/.config/nvim/lua/user_functions/tasks.lua
local M = {}

-- Import the create_floating_scratch function from utils.lua
local utils = require "user_functions.utils"

function M.create_or_update_task()
  local current_line = vim.fn.getline "."
  local cursor_pos = vim.fn.col "."
  local file_path = vim.fn.expand "%:p" -- Get full path of current file
  local line_number = vim.fn.line "." -- Get current line number

  -- Keywords we are looking for
  local keywords = { "TODO", "HACK", "NOTE", "PERF", "TEST", "WARN" }

  for _, keyword in ipairs(keywords) do
    local start_index, end_index = string.find(current_line, keyword)
    if start_index then
      local task_description = string.sub(current_line, end_index + 2, cursor_pos - 1)
      task_description = string.gsub(task_description, "%(piotr1215%)", "")
      local task_tag = "+" .. string.lower(keyword)

      -- Ask for project and other tags
      local project = vim.fn.input "Enter project name: "
      local additional_tags_input = vim.fn.input "Enter additional tags separated by spaces: "
      local additional_tags = {}

      -- Prefix each additional tag with a "+"
      for tag in additional_tags_input:gmatch "%S+" do
        table.insert(additional_tags, "+" .. tag)
      end

      -- Prepare the task command
      local task_cmd = string.format('task add %s "%s"', task_tag, task_description)

      -- Add additional tags if available
      if #additional_tags > 0 then
        task_cmd = task_cmd .. " " .. table.concat(additional_tags, " ")
      end

      -- Add project if available
      if project and #project > 0 then
        task_cmd = task_cmd .. " project:" .. project
      end

      -- Execute the task add command
      local output = vim.fn.system(task_cmd)
      print("Output: ", output)

      for line in output:gmatch "[^\r\n]+" do
        local task_id = string.match(line, "Created task (%d+)%.")
        if task_id then
          print("Task ID extracted: ", task_id)

          -- Annotate task with filename and line number in the nvimline format
          local annotation = string.format("nvimline:%s:%s", line_number, file_path)
          local annotate_cmd = string.format('task %s annotate "%s"', task_id, annotation)
          local annotate_output = vim.fn.system(annotate_cmd)

          print("Annotation output: ", annotate_output)
          return
        else
          print "Failed to extract task ID"
        end
      end
    end
  end
end

vim.api.nvim_set_keymap(
  "i",
  "<C-T>",
  "<Cmd>lua require('user_functions.tasks').create_or_update_task()<CR>",
  { noremap = true, silent = true }
)

function M.mark_task_done()
  -- Get the current line and parse it
  local line = vim.api.nvim_get_current_line()
  print("Original line: ", line)

  -- Uncomment the line
  vim.cmd [[execute "normal \<Plug>NERDCommenterUncomment"]]
  line = vim.api.nvim_get_current_line()
  print("Uncommented line: ", line)

  local patterns = { "TODO:", "HACK:", "NOTE:", "PERF:", "TEST:", "WARN:" }
  local taskDescription = nil
  for _, pattern in ipairs(patterns) do
    local start_idx = string.find(line, pattern)
    if start_idx then
      taskDescription = string.sub(line, start_idx + string.len(pattern) + 1)
      break
    end
  end
  print("Task description: ", taskDescription or "nil")

  -- If a task description was found, mark it as done
  if taskDescription then
    local output = vim.fn.system("yes | task description~'" .. taskDescription .. "' done")
    print("Command output: ", output)
    -- Check the command's output to make sure the task was marked done
    if string.find(output, "Completed") then
      -- Delete the current line
      vim.cmd [[normal dd]]
    end
  end
end
vim.api.nvim_set_keymap(
  "n",
  "<leader>dt",
  "<Cmd>lua require('user_functions.tasks').mark_task_done()<CR>",
  { noremap = true, silent = true }
)

function M.go_to_task_in_taskwarrior_tui()
  -- Get the current line and save it as the original line
  local original_line = vim.api.nvim_get_current_line()

  -- Uncomment the line
  vim.cmd [[execute "normal \<Plug>NERDCommenterUncomment"]]
  local uncommented_line = vim.api.nvim_get_current_line()

  local patterns = { "TODO:", "HACK:", "NOTE:", "PERF:", "TEST:", "WARN:" }
  local taskDescription = nil

  for _, pattern in ipairs(patterns) do
    local start_idx = string.find(uncommented_line, pattern)
    if start_idx then
      taskDescription = string.sub(uncommented_line, start_idx + string.len(pattern) + 1)
      taskDescription = string.sub(taskDescription, 1, 50)
      break
    end
  end

  -- If a task description was found, use it to go to the task in taskwarrior-tui
  if taskDescription then
    -- print("Sleeping for 2 seconds before tmux switch...")
    -- vim.cmd("sleep 2") -- sleep for 2 seconds
    local output = vim.fn.system(" ~/dev/dotfiles/scripts/__switch_to_tui.sh '" .. taskDescription .. "'")
  end

  -- Replace the line back with the original
  vim.api.nvim_set_current_line(original_line)
end
vim.api.nvim_set_keymap(
  "n",
  "<leader>gt",
  "<Cmd>lua require('user_functions.tasks').go_to_task_in_taskwarrior_tui()<CR>",
  { noremap = true, silent = true }
)
function M.process_task_list(start_line, end_line, ...)
  local args = { ... }
  local modifiers = table.concat(args, " ")
  local lines

  -- If no range is provided, use the entire buffer.
  if not start_line or not end_line then
    start_line, end_line = 1, vim.api.nvim_buf_line_count(0)
  end

  lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  local new_lines = { "#!/usr/bin/env bash", "set -eo pipefail" }

  for _, line in ipairs(lines) do
    local trimmed_line = line:gsub("^[•*%-%+]+%s*", "")
    local links = {}

    trimmed_line = trimmed_line:gsub("(https?://[%w%.%-%_/&%?=%~]+)", function(link)
      table.insert(links, link)
      return ""
    end)

    if #trimmed_line > 0 then
      -- No more "\n" before "# Adding task:"; instead, just ensure it's a new entry in the table.
      table.insert(new_lines, "") -- Ensure there's an empty line before adding a new task if desired.
      table.insert(new_lines, "# Adding task: " .. trimmed_line)
      table.insert(
        new_lines,
        "output=$(task add " .. (modifiers ~= "" and modifiers .. " " or "") .. '"' .. trimmed_line .. '")'
      )
      table.insert(
        new_lines,
        'task_id=$(echo "$output" | grep -o "Created task [0-9]*." | cut -d " " -f 3 | tr -d ".")'
      )

      for _, link in ipairs(links) do
        table.insert(new_lines, "task $task_id annotate -- " .. link)
      end
    end
  end

  -- Call the create_floating_scratch function from utils.lua
  utils.create_floating_scratch(new_lines)
end

function M.my_custom_complete(arg_lead, cmd_line, cursor_pos)
  -- This is your list of arguments.
  local items = { "project:", "due:", "+next", "duration:" }

  -- Filter the items based on the argument lead.
  local matches = {}
  for _, item in ipairs(items) do
    if item:find(arg_lead) == 1 then
      table.insert(matches, item)
    end
  end

  return matches
end

vim.api.nvim_create_user_command("ProcessTaskList", function(input)
  M.process_task_list(1, vim.api.nvim_buf_line_count(0), unpack(vim.split(input.args, " ")))
end, { nargs = "*" })

return M
