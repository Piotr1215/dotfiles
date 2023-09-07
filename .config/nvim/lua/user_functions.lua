-- TODO: consider splitting the whole file into smaller parts
local wk = require("which-key")

-- Store the zoom state
local zoomed = false

-- Function to toggle zoom
function _G.toggle_zoom()
  if zoomed then
    vim.api.nvim_command('wincmd =')
    zoomed = false
  else
    vim.api.nvim_command('wincmd _')
    vim.api.nvim_command('wincmd |')
    zoomed = true
  end
end

-- Key mapping
vim.api.nvim_set_keymap('n', '<leader>zw', ':lua toggle_zoom()<CR>', { noremap = true, silent = true })

-- TODO: functionality to move back from file to taskwarrior or task

function _G.mark_task_done()
  -- Get the current line and parse it
  local line = vim.api.nvim_get_current_line()
  print("Original line: ", line)

  -- Uncomment the line
  vim.cmd [[execute "normal \<Plug>NERDCommenterUncomment"]]
  line = vim.api.nvim_get_current_line()
  print("Uncommented line: ", line)

  local patterns = { 'TODO:', 'HACK:', 'NOTE:', 'PERF:', 'TEST:', 'WARN:' }
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

-- Map the function to a key
vim.api.nvim_set_keymap('n', '<leader>dt', [[<Cmd>lua mark_task_done()<CR>]], { noremap = true, silent = true })
-- Function for creating or updating a Taskwarrior task
function _G.create_or_update_task()
  local current_line = vim.fn.getline('.')
  local cursor_pos = vim.fn.col('.')
  local file_path = vim.fn.expand('%:p') -- Get full path of current file
  local line_number = vim.fn.line('.')   -- Get current line number

  -- Keywords we are looking for
  local keywords = { "TODO", "HACK", "NOTE", "PERF", "TEST", "WARN" }

  for _, keyword in ipairs(keywords) do
    local start_index, end_index = string.find(current_line, keyword)
    if start_index then
      local task_description = string.sub(current_line, end_index + 2, cursor_pos - 1)
      local task_tag = "+" .. string.lower(keyword)

      -- Ask for project and other tags
      local project = vim.fn.input('Enter project name: ')
      local additional_tags_input = vim.fn.input('Enter additional tags separated by spaces: ')
      local additional_tags = {}

      -- Prefix each additional tag with a "+"
      for tag in additional_tags_input:gmatch("%S+") do
        table.insert(additional_tags, "+" .. tag)
      end

      -- Prepare the task command
      local task_cmd = string.format("task add %s \"%s\"", task_tag, task_description)

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

      for line in output:gmatch("[^\r\n]+") do
        local task_id = string.match(line, "Created task (%d+)%.")
        if task_id then
          print("Task ID extracted: ", task_id)

          -- Annotate task with filename and line number in the nvimline format
          local annotation = string.format("nvimline:%s:%s", line_number, file_path)
          local annotate_cmd = string.format("task %s annotate \"%s\"", task_id, annotation)
          local annotate_output = vim.fn.system(annotate_cmd)

          print("Annotation output: ", annotate_output)
          return
        else
          print("Failed to extract task ID")
        end
      end
    end
  end
end

-- Bind Ctrl-T in insert mode to call the create_or_update_task function
vim.api.nvim_set_keymap('i', '<C-T>', [[<Cmd>lua create_or_update_task(vim.fn.getline('.'))<CR>]],
  { noremap = true, silent = true })

local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

function _G.insert_file_path()
  require('telescope.builtin').find_files({
    cwd = '~/dev', -- Set the directory to search
    attach_mappings = function(_, map)
      map('i', '<CR>', function(prompt_bufnr)
        local selected_file = action_state.get_selected_entry(prompt_bufnr).path
        actions.close(prompt_bufnr)

        -- Replace the home directory with ~
        selected_file = selected_file:gsub(vim.fn.expand("$HOME"), "~")

        -- Ask the user if they want to insert the full path or just the file name
        local choice = vim.fn.input("Insert full path or file name? (n[ame]/p[ath]): ")
        local text_to_insert
        if choice == 'p' then
          text_to_insert = selected_file
        elseif choice == 'n' then
          text_to_insert = vim.fn.fnamemodify(selected_file, ':t')
        end

        -- Move the cursor back one position if it's between quotes
        local col = vim.fn.col('.') - 1
        if vim.fn.getline('.')[col] == "'" or vim.fn.getline('.')[col] == '"' then
          vim.fn.cursor(vim.fn.line('.'), col)
        end

        -- Insert the text at the cursor position
        vim.api.nvim_put({ text_to_insert }, 'c', true, true)
      end)
      return true
    end,
  })
end

vim.api.nvim_set_keymap('i', '<M-i>', [[<Cmd>lua insert_file_path()<CR>]], { noremap = true, silent = true })

function _G.toggle_function_folding()
  if vim.wo.foldenable and vim.wo.foldmethod == "expr" then
    print("Disabling folding")
    vim.cmd('setlocal nofoldenable')
    vim.cmd('setlocal foldmethod=manual')
  else
    print("Enabling folding")
    vim.cmd('setlocal foldenable')
    vim.cmd('setlocal foldmethod=expr')
    vim.cmd([[setlocal foldexpr=getline(v:lnum)=~'^function\\s\\+\\w\\+\\s*()'?'a1':getline(v:lnum)=~'}'?'s1':'=']])
  end
end

vim.cmd("command! Fold lua _G.toggle_function_folding()")

function _G.yank_matching_lines()
  local search_pattern = vim.fn.getreg('/')
  if search_pattern ~= '' then
    local matching_lines = {}
    for line_number = 1, vim.fn.line('$') do
      local line = vim.fn.getline(line_number)
      if vim.fn.match(line, search_pattern) ~= -1 then
        table.insert(matching_lines, line)
      end
    end
    if #matching_lines > 0 then
      local original_filetype = vim.bo.filetype
      vim.fn.setreg('+', table.concat(matching_lines, '\n'))
      vim.cmd('new')
      vim.cmd('0put +')
      vim.bo.filetype = original_filetype
    else
      print("No matches found")
    end
  end
end

vim.api.nvim_set_keymap('n', '<Leader>ya', ':lua _G.yank_matching_lines()<CR>', { noremap = true, silent = true })

function _G.create_word_selection_mappings()
  for i = 2, 5 do
    local count = 2 * i - 1
    vim.api.nvim_set_keymap('n', 'v' .. i, 'v' .. count .. 'iw', { noremap = true })
    wk.register({ ['v' .. i] = { 'v' .. count .. 'iw', 'Select ' .. i .. ' words' } }, { mode = 'n', prefix = '' })
  end
  vim.api.nvim_set_keymap('n', '_', 'vg_', { noremap = true })
  wk.register({ ['_'] = { 'vg_', 'Select inside underscored word' } }, { mode = 'n', prefix = '' })
end

create_word_selection_mappings()

-- Custom f command function
-- This is needed because ;; is mapped to enter command mode
vim.cmd([[
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
]])

-- Map f to the custom f command function so that pressing f and ; works as expected
vim.api.nvim_set_keymap("n", "f", ":call CustomF(0)<CR>", {})
vim.api.nvim_set_keymap("v", "f", ":call CustomF(0)<CR>", {})
vim.api.nvim_set_keymap("n", "F", ":call CustomF(1)<CR>", {})
vim.api.nvim_set_keymap("v", "F", ":call CustomF(1)<CR>", {})

function _G.my_custom_complete(arg_lead, cmd_line, cursor_pos)
  -- This is your list of arguments.
  local items = { "project:", "due:", "+next" }

  -- Filter the items based on the argument lead.
  local matches = {}
  for _, item in ipairs(items) do
    if item:find(arg_lead) == 1 then
      table.insert(matches, item)
    end
  end

  return matches
end

function _G.process_task_list(...)
  local args = { ... }
  local modifiers = table.concat(args, " ")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local new_lines = {}

  -- Adding shebang and setting options
  table.insert(new_lines, '#!/usr/bin/env bash')
  table.insert(new_lines, 'set -eo pipefail')

  for _, line in ipairs(lines) do
    local trimmed_line = line:gsub('^[•*%-%+]+%s*', '') -- Remove bullet points
    local links = {}

    -- Extract http/https links and remove them from the task description
    trimmed_line = trimmed_line:gsub('(https?://[%w%.%-%_/&%?=%~]+)', function(link)
      table.insert(links, link)
      return ''
    end)

    if #trimmed_line > 0 then
      table.insert(new_lines,
        'output=$(task add ' .. (modifiers ~= '' and modifiers .. ' ' or '') .. '"' .. trimmed_line .. '")')
      table.insert(new_lines, 'task_id=$(echo "$output" | grep -o "Created task [0-9]*." | cut -d " " -f 3 | tr -d ".")')

      -- Annotate the task with the extracted links
      for _, link in ipairs(links) do
        table.insert(new_lines, 'task $task_id annotate -- ' .. link)
      end
    else
      table.insert(new_lines, '') -- Keep empty lines
    end
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)
end

vim.api.nvim_set_keymap('n', '<Leader>pt', ':lua _G.process_task_list()<CR>', { noremap = true, silent = true })

vim.cmd([[
  command! -nargs=* -complete=customlist,v:lua.my_custom_complete ProcessTasks :lua _G.process_task_list(<f-args>)
]])
