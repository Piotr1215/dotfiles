local key = vim.api.nvim_set_keymap
local set_up_telescope = function()
  local set_keymap = function(mode, bind, cmd)
    key(mode, bind, cmd, { noremap = true, silent = true })
  end
  set_keymap('n', '<leader><leader>', [[<cmd>lua require('telescope.builtin').buffers()<CR>]])
  --set_keymap('n', '<leader>tf', [[<cmd>lua require('telescope.builtin').find_files({find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<CR>]])
  set_keymap('n', '<leader>tf', [[<cmd>lua require('telescope.builtin').find_files(})<CR>]])
  set_keymap('n', '<leader>tg', [[<cmd>lua require('telescope.builtin').live_grep()<CR>]])
  set_keymap('n', '<leader>to', [[<cmd>lua require('telescope.builtin').oldfiles()<CR>]])
  set_keymap('n', '<leader>ts', [[<cmd>lua require('telescope.builtin').grep_string()<CR>]])
  set_keymap('n', '<leader>tb', [[<cmd>lua require('telescope.builtin').current_buffer_fuzzy_find()<CR>]])
  set_keymap('n', '<leader>th', [[<cmd>lua require('telescope.builtin').help_tags()<CR>]])
  set_keymap('n', '<leader>tt', [[<cmd>lua require('telescope.builtin').tags()<CR>]])
  set_keymap('n', '<leader>tT', [[<cmd>lua require('telescope.builtin').tags{ only_current_buffer = true }<CR>]])
  -- set_keymap('n', '<leader>sf', [[<cmd>lua vim.lsp.buf.formatting()<CR>]])
end

set_up_telescope()
