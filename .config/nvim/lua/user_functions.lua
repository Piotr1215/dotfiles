local wk = require("which-key")

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

