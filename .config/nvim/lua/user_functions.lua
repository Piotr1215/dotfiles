local wk = require "which-key"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local unpack = unpack or table.unpack
local zoomed = false

function _G.select_note_type_and_create()
  local note_types = {
    'projects', 'topics', 'meetings', 'reviews', 'how-tos'
  }

  vim.ui.select(note_types, { prompt = 'Select note type:' }, function(choice)
    if not choice then return end
    local note_title = vim.fn.input('Note title: ')
    if note_title ~= "" then
      -- Directly concatenate without additional quotes
      vim.cmd('CreateNoteWithTemplate ' .. choice .. ' ' .. note_title)
    end
  end)
end

vim.api.nvim_set_keymap('n', '<leader>oc', ':lua select_note_type_and_create()<CR>', { noremap = true, silent = true })

function _G.create_note_with_template(template_type, note_title)
  -- Define base directory for notes
  local base_dir = "Notes"
  -- Define the command to create a new note using ObsidianNew
  local obsidian_new_cmd = string.format(":ObsidianNew %s/%s/%s", base_dir, template_type, note_title)
  vim.api.nvim_command(obsidian_new_cmd)

  -- Wait briefly to ensure command execution completion
  vim.wait(100, function() end)

  -- Insert two empty lines at the end
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "", "" })

  -- Move the cursor to the last line of the file
  vim.api.nvim_command("normal G")

  -- Apply the template based on the type
  local obsidian_template_cmd = string.format(":ObsidianTemplate %s.md", template_type)
  vim.api.nvim_command(obsidian_template_cmd)
end

vim.api.nvim_create_user_command('CreateNoteWithTemplate', function(input)
  -- Split input to get template type and note title
  local args = vim.split(input.args, " ", { trimempty = true })
  if #args < 2 then
    print("Usage: CreateNoteWithTemplate <template_type> <note_title>")
    return
  end
  local template_type = args[1]

  local note_title = table.concat({ select(2, unpack(args)) }, " ")

  create_note_with_template(template_type, note_title)
end, { nargs = "+" })

-- Inserts a TODO comment at the current cursor position and then comments out the original line.
function _G.insert_todo_and_comment()
  -- Insert the TODO text at the current cursor position
  local line = vim.api.nvim_get_current_line()
  print("Original line: ", line)

  vim.api.nvim_put({ 'TODO:(piotr1215)' }, '', true, true)
  -- Uncomment the line
  vim.cmd [[execute "normal \<Plug>NERDCommenterComment"]]
  vim.cmd [[execute "normal \A "]]
end

vim.api.nvim_set_keymap('i', '<c-a>', '<C-o>:lua insert_todo_and_comment()<CR>', { noremap = true, silent = true })

function _G.swapWords()
  local current_line = vim.api.nvim_get_current_line()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local col = cursor_pos[2] + 1 -- Adjusting for Lua's 1-based indexing

  -- Extract WORDs from the current line
  local words = {}
  for word in current_line:gmatch("%S+") do
    table.insert(words, word)
  end

  -- Find the current and next WORD
  local current_word, next_word
  local current_word_start, next_word_start
  local index = 0
  for _, word in ipairs(words) do
    index = current_line:find(word, index + 1, true)
    if index < col then
      current_word = word
      current_word_start = index
    elseif index >= col and not next_word then
      next_word = word
      next_word_start = index
      break
    end
  end

  -- Swap the WORDs if possible
  if current_word and next_word then
    local swapped_line = current_line:sub(1, current_word_start - 1) .. next_word
    swapped_line = swapped_line .. current_line:sub(current_word_start + #current_word, next_word_start - 1)
    swapped_line = swapped_line .. current_word .. current_line:sub(next_word_start + #next_word)
    vim.api.nvim_set_current_line(swapped_line)
    -- Set the new cursor position
    local new_col = next_word_start + #next_word - #current_word
    vim.api.nvim_win_set_cursor(0, { cursor_pos[1], new_col })
  end
end

-- Key binding
vim.api.nvim_set_keymap('n', '<leader>sw', '<cmd>lua swapWords()<cr>', { noremap = true, silent = true })

function _G.get_tmux_working_directory()
  local handle = io.popen("tmux display-message -p -F '#{pane_current_path}'")
  if handle then
    local result = handle:read("*a")
    handle:close()
    if result and result ~= "" then
      local trimmed_result = result:gsub("%s+", "")
      return trimmed_result
    else
      print("No result obtained or result is empty")
    end
  else
    print("Failed to create handle")
  end
end

_G.operator_callback = function()
  local s_pos = vim.fn.getpos("'<")
  local e_pos = vim.fn.getpos("'>")
  local s_line, s_col = s_pos[2], s_pos[3]
  local e_line, e_col = e_pos[2], e_pos[3]
  local register_content = vim.fn.getreg('a') -- Get the content of the "a" register

  -- Split the register content into lines
  local replacement_lines = vim.split(register_content, '\n')

  -- Replace the visually selected text with the lines from the register
  vim.api.nvim_buf_set_text(0, s_line - 1, s_col - 1, e_line - 1, e_col, replacement_lines)
end

function _G.replace_with_register()
  print("Running replace_with_register function")
  -- Call the register picker from telescope
  require('telescope.builtin').registers({
    attach_mappings = function(prompt_bufnr, map)
      print("Register picker called from telescope")
      actions.select_default:replace(function()
        print("Inside actions.select_default:replace function")
        -- Close the picker
        actions.close(prompt_bufnr)
        print("Picker closed")

        -- Get the selected register
        local selection = action_state.get_selected_entry()
        print(vim.inspect(selection))

        -- Get the content of the selected register
        local register_content = selection.content
        print(vim.inspect(register_content))

        -- Set the content of the "a" register
        vim.fn.setreg('a', register_content)

        -- Set up the operator callback
        vim.o.operatorfunc = "v:lua._G.operator_callback"
        vim.api.nvim_feedkeys("g@`<", "ni", false) -- This triggers the operator callback on the visual selection

        print("Substitute command executed")
      end)
      print("Exited from actions.select_default:replace function")
      return true -- Keep the rest of the mappings
    end
  })
end

-- Create a keymap to call the replace_with_register function
vim.api.nvim_set_keymap('v', '<leader>rg', [[:lua replace_with_register()<CR>]], { noremap = true, silent = true })
-- Create a flag to keep track of whether the prompt has been shown
local prompt_shown = false

function _G.test_delete_videos()
  local filepath = vim.fn.expand('%:p')                                  -- Get the full path of the current file
  if filepath == '/home/decoder/vids_playlist.m3u' then
    local lines = vim.fn.readfile(filepath)                              -- Read the file into a table
    local content = table.concat(lines, '\n'):gsub("^%s*(.-)%s*$", "%1") -- Join the table into a string and trim whitespace
    if content == "" and not prompt_shown then                           -- Check if the file is empty and prompt was not shown yet
      local answer = vim.fn.input('Delete all video files in ~/Video? (y/n): ')
      if answer:lower() == 'y' then
        local handle = io.popen(
          'find /home/decoder/Videos -type f \\( -name "*.mp4" -o -name "*.webm" \\) -exec rm -f {} + 2>&1')
        local output = handle:read("*a")
        handle:close()

        -- Count deleted files
        local _, count = string.gsub(output, '\n', '\n')
        if count > 0 then
          -- Display how many files were deleted
          print(count .. " video files deleted.")
        else
          print(output) -- Pass through the system error message
        end
      end
      prompt_shown = true  -- Set the flag to true, so the prompt won't be shown again
    else
      prompt_shown = false -- Reset the flag, so the prompt can be shown again
    end
  end
end

-- Hook the function to the TextChanged and TextChangedI events
vim.cmd [[ autocmd BufWritePost *.m3u lua test_delete_videos() ]]

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

_G.folding_enabled = false


-- Toggle function
function _G.toggle_function_folding()
  print("toggle_function_folding called") -- Debug print
  if _G.folding_enabled then
    print("Disabling folds")              -- Debug print
    vim.cmd "setlocal nofoldenable"
    vim.cmd "normal zR"                   -- Unfold all folds
    _G.folding_enabled = false
  else
    print("Enabling folds") -- Debug print
    vim.cmd "setlocal foldenable"
    vim.cmd "setlocal foldmethod=expr"
    vim.cmd "normal zM" -- Fold all folds
    _G.folding_enabled = true
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

-- Trigger ranger in neovim inside a tmux popup
-- Current file path will be the main path
-- PROJECT: ranger-tmux-setup
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

function _G.redirect_messages_to_clipboard()
  -- Redirect messages to clipboard register
  vim.cmd("redir @+")
  vim.cmd("messages")
  vim.cmd("redir END")
end

-- Map <leader>msg to the function
vim.api.nvim_set_keymap('n', '<leader>msg', [[:lua redirect_messages_to_clipboard()<CR>]],
  { noremap = true, silent = true })

function _G.add_empty_lines(below)
  local count = vim.v.count1
  local lines = {}
  for _ = 1, count do
    table.insert(lines, "")
  end

  if below then
    vim.fn.append(vim.fn.line('.'), lines)
    vim.cmd('normal! ' .. count .. 'j')
  else
    vim.fn.append(vim.fn.line('.') - 1, lines)
    vim.cmd('normal! ' .. count .. 'k')
  end
end

function _G.execute_file_and_show_output()
  -- Define the command to execute the current file
  local cmd = "bash " .. vim.fn.expand('%:p') -- '%:p' expands to the current file path

  -- Execute the command and capture its output
  local output = vim.fn.systemlist(cmd)

  -- Check for execution error
  if vim.v.shell_error ~= 0 then
    table.insert(output, 1, "Error executing file:")
  end

  -- Call the function to create a floating scratch buffer with the output
  _G.create_floating_scratch(output)
end

function _G.create_floating_scratch(content)
  -- Get editor dimensions
  local width = vim.api.nvim_get_option("columns")
  local height = vim.api.nvim_get_option("lines")

  -- Calculate the floating window size
  local win_height = math.ceil(height * 0.8) + 2 -- Adding 2 for the border
  local win_width = math.ceil(width * 0.8) + 2   -- Adding 2 for the border

  -- Calculate window's starting position
  local row = math.ceil((height - win_height) / 2)
  local col = math.ceil((width - win_width) / 2)

  -- Create a buffer and set it as a scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'sh') -- for syntax highlighting

  -- Create the floating window with a border and set some options
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = row,
    col = col,
    width = win_width,
    height = win_height,
    border = 'single' -- You can also use 'double', 'rounded', or 'solid'
  })

  -- Check if we've got content to populate the buffer with
  if content then
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, content)
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, { "This is a scratch buffer in a floating window." })
  end

  vim.api.nvim_win_set_option(win, 'wrap', false)
  vim.api.nvim_win_set_option(win, 'cursorline', true)

  -- Map 'q' to close the buffer in this window
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':q!<CR>', { noremap = true, silent = true })
end

function _G.execute_visual_selection()
  -- Yank visual selection into register "a"
  vim.cmd('normal! gvy')
  local lines = vim.fn.getreg('"')

  -- Clean up the lines and print for debugging
  lines = lines:gsub("[\n\r]", ""):gsub("'", [['"'"']])
  print("Executing command: ", lines)

  -- Execute command and capture output
  local result = vim.fn.systemlist("bash -c " .. "'" .. lines .. "'")

  -- Create a floating scratch buffer and populate it with the output
  _G.create_floating_scratch(result)
end

-- Map <leader>es in visual mode to the function
vim.api.nvim_set_keymap('x', '<leader>ex', [[:lua execute_visual_selection()<CR>]], { noremap = true, silent = true })

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
