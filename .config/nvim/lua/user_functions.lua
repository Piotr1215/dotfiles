local wk = require("which-key")

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

function _G.process_task_list(...)
  local args = { ... }
  local modifiers = table.concat(args, " ")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local new_lines = {}

  for _, line in ipairs(lines) do
    local trimmed_line = line:gsub("^[•*%-%+]+%s*", "") -- Remove bullet points
    if #trimmed_line > 0 then
      if modifiers == "" then
        table.insert(new_lines, "task add \"" .. trimmed_line .. "\"")
      else
        table.insert(new_lines, "task add " .. modifiers .. " \"" .. trimmed_line .. "\"")
      end
    else
      table.insert(new_lines, "") -- Keep empty lines
    end
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)
end

vim.api.nvim_set_keymap('n', '<Leader>pt', ':lua _G.process_task_list()<CR>', { noremap = true, silent = true })

vim.cmd([[
  command! -nargs=* ProcessTasks :lua _G.process_task_list(<f-args>)
]])
