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
