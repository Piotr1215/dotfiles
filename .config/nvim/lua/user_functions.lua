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

function _G.generate_mappings_command(action, inner_outer, text_object)
  local register = string.lower(action)
  return '"' .. register .. action .. inner_outer .. text_object
end

function _G.generate_mappings(action, inner_outer, text_object)
  local command = _G.generate_mappings_command(action, inner_outer, text_object)
  vim.api.nvim_set_keymap('n', action .. inner_outer .. text_object, command, {noremap = true})
end

-- Generate the mappings for change and delete actions
local actions = {'c', 'd'}
local inner_outer = {'i', 'a'}
local text_objects = {'w', 'W', ')', '.', 'b', 'q', 'p', '`', "'", '"'}

for _, action in ipairs(actions) do
  for _, io in ipairs(inner_outer) do
    for _, text_object in ipairs(text_objects) do
      _G.generate_mappings(action, io, text_object)
    end
  end
end

