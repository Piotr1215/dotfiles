local wk = require "which-key"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local zoomed = false

--- Processes a task list and generates a shell script to handle tasks via the taskwarrior CLI.
-- This function modifies the current buffer, adding lines that invoke taskwarrior commands.
-- The resulting lines will include any additional modifiers passed to the function.
-- @param ... A variable number of string modifiers to pass to the `task add` command
function _G.process_task_list(...)
  local args = { ... }
  local modifiers = table.concat(args, " ")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local new_lines = {}

  -- Adding shebang and setting options
  table.insert(new_lines, "#!/usr/bin/env bash")
  table.insert(new_lines, "set -eo pipefail")

  for _, line in ipairs(lines) do
    local trimmed_line = line:gsub("^[•*%-%+]+%s*", "") -- Remove bullet points
    local links = {}

    -- Extract http/https links and remove them from the task description
    trimmed_line = trimmed_line:gsub("(https?://[%w%.%-%_/&%?=%~]+)", function(link)
      table.insert(links, link)
      return ""
    end)

    if #trimmed_line > 0 then
      table.insert(
        new_lines,
        "output=$(task add " .. (modifiers ~= "" and modifiers .. " " or "") .. '"' .. trimmed_line .. '")'
      )
      table.insert(
        new_lines,
        'task_id=$(echo "$output" | grep -o "Created task [0-9]*." | cut -d " " -f 3 | tr -d ".")'
      )

      -- Annotate the task with the extracted links
      for _, link in ipairs(links) do
        table.insert(new_lines, "task $task_id annotate -- " .. link)
      end
    else
      table.insert(new_lines, "") -- Keep empty lines
    end
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)
end

--- Custom completion function specifically for `process_task_list` in Neovim's command-line interface.
-- This function provides argument suggestions for the `process_task_list` function when called from the command line.
-- @param arg_lead The leading portion of the argument to be completed.
-- @param cmd_line The entire command line input up to this point.
-- @param cursor_pos The position of the cursor within the command line.
-- @return A table containing argument suggestions that match the prefix (arg_lead) for `process_task_list`.
function _G.my_custom_complete(arg_lead, cmd_line, cursor_pos)
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

function _G.create_word_selection_mappings()
  for i = 2, 5 do
    local count = 2 * i - 1
    vim.api.nvim_set_keymap("n", "v" .. i, "v" .. count .. "iw", { noremap = true })
    wk.register({ ["v" .. i] = { "v" .. count .. "iw", "Select " .. i .. " words" } }, { mode = "n", prefix = "" })
  end
  vim.api.nvim_set_keymap("n", "_", "vg_", { noremap = true })
  wk.register({ ["_"] = { "vg_", "Select inside underscored word" } }, { mode = "n", prefix = "" })
end

function _G.toggle_function_folding()
  if vim.wo.foldenable then
    vim.cmd "setlocal nofoldenable"
    vim.cmd "normal zR" -- Unfold all folds
    vim.cmd 'echo "Disabling folding"'
  else
    vim.cmd "setlocal foldenable"
    vim.cmd "setlocal foldmethod=expr"
    vim.cmd "normal zM" -- Fold all folds
    print "Enabling folding"
  end
end

function _G.insert_file_path()
  require("telescope.builtin").find_files {
    cwd = "~/dev", -- Set the directory to search
    attach_mappings = function(_, map)
      map("i", "<CR>", function(prompt_bufnr)
        local selected_file = action_state.get_selected_entry(prompt_bufnr).path
        actions.close(prompt_bufnr)

        -- Replace the home directory with ~
        selected_file = selected_file:gsub(vim.fn.expand "$HOME", "~")

        -- Ask the user if they want to insert the full path or just the file name
        local choice = vim.fn.input "Insert full path or file name? (n[ame]/p[ath]): "
        local text_to_insert
        if choice == "p" then
          text_to_insert = selected_file
        elseif choice == "n" then
          text_to_insert = vim.fn.fnamemodify(selected_file, ":t")
        end

        -- Move the cursor back one position
        local col = vim.fn.col "." - 1
        vim.fn.cursor(vim.fn.line ".", col)

        -- Insert the text at the cursor position
        vim.api.nvim_put({ text_to_insert }, "c", true, true)
      end)
      return true
    end,
  }
end

function _G.create_or_update_task()
  local current_line = vim.fn.getline "."
  local cursor_pos = vim.fn.col "."
  local file_path = vim.fn.expand "%:p" -- Get full path of current file
  local line_number = vim.fn.line "."   -- Get current line number

  -- Keywords we are looking for
  local keywords = { "TODO", "HACK", "NOTE", "PERF", "TEST", "WARN" }

  for _, keyword in ipairs(keywords) do
    local start_index, end_index = string.find(current_line, keyword)
    if start_index then
      local task_description = string.sub(current_line, end_index + 2, cursor_pos - 1)
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

function _G.mark_task_done()
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

function _G.go_to_task_in_taskwarrior_tui()
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

function _G.ranger_popup_in_tmux()
  -- Get the directory of the current file in Neovim
  local current_file = vim.fn.expand "%:p:h"

  -- Formulate the tmux command with either the file directory or the pane's current path
  local tmux_command = "tmux popup -d '" .. current_file .. "' -E -h 95% -w 95% -x 100% 'ranger'"

  -- Execute the tmux command
  os.execute(tmux_command)
end

function _G.toggle_zoom()
  if zoomed then
    vim.api.nvim_command "wincmd ="
    zoomed = false
  else
    vim.api.nvim_command "wincmd _"
    vim.api.nvim_command "wincmd |"
    zoomed = true
  end
end

function _G.print_current_file_dir()
  local dir = vim.fn.expand "%:p:h"
  if dir ~= "" then
    print(dir)
  end
end

-- Custom f command function
-- This is needed because ;; is mapped to enter command mode
vim.cmd [[
function! CustomF(backwards)
  let l:char = nr2char(getchar())
  if a:backwards
    execute "normal! F" . l:char
  else
    execute "normal! f" . l:char
  endif
  nnoremap ; ;
  vnoremap ; ;
endfunction
]]
vim.cmd "command! GetCurrentFileDir lua print_current_file_dir()"

-- Key mappings
vim.api.nvim_set_keymap("n", "<leader>zw", ":lua toggle_zoom()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>mr", ":lua ranger_popup_in_tmux()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap(
  "n",
  "<leader>gt",
  [[<Cmd>lua go_to_task_in_taskwarrior_tui()<CR>]],
  { noremap = true, silent = true }
)
vim.api.nvim_set_keymap("n", "<leader>dt", [[<Cmd>lua mark_task_done()<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap(
  "i",
  "<C-T>",
  [[<Cmd>lua create_or_update_task(vim.fn.getline('.'))<CR>]],
  { noremap = true, silent = true }
)
vim.cmd "command! Fold lua _G.toggle_function_folding()"

vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.*",
  callback = function()
    vim.defer_fn(function()
      _G.toggle_function_folding()
      _G.toggle_function_folding()
      vim.cmd "normal zx"
    end, 50) -- Delay for 50 milliseconds
  end,
})

vim.api.nvim_set_keymap("i", "<M-i>", [[<Cmd>lua insert_file_path()<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "fld", [[<Cmd>lua _G.toggle_function_folding()<CR>]], { noremap = true, silent = false })
vim.api.nvim_set_keymap("n", "f", ":call CustomF(0)<CR>", {})
vim.api.nvim_set_keymap("v", "f", ":call CustomF(0)<CR>", {})
vim.api.nvim_set_keymap("n", "F", ":call CustomF(1)<CR>", {})
vim.api.nvim_set_keymap("v", "F", ":call CustomF(1)<CR>", {})
vim.api.nvim_set_keymap("n", "<Leader>pt", ":lua _G.process_task_list()<CR>", { noremap = true, silent = true })
vim.cmd [[
  command! -nargs=* -complete=customlist,v:lua.my_custom_complete ProcessTasks :lua _G.process_task_list(<f-args>)
]]

create_word_selection_mappings()
