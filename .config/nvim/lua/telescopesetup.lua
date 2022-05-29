require('telescope').setup{
--  defaults   = {},
--  pickers    = {},
  extensions = {
    fzf = {
      fuzzy = true,                    -- false will only do exact matching
      override_generic_sorter = true,  -- override the generic sorter
      override_file_sorter = true,     -- override the file sorter
      case_mode = "smart_case",        -- or "ignore_case" or "respect_case"
      file_browser = true,
    }
  }
}

require('telescope').load_extension('file_browser')
local key = vim.api.nvim_set_keymap
local set_up_telescope = function()
  local set_keymap = function(mode, bind, cmd)
    key(mode, bind, cmd, { noremap = true, silent = true })
  end
  set_keymap('n', '<leader><leader>', [[<cmd>lua require('telescope.builtin').buffers()<CR>]])
  --set_keymap('n', '<leader>tf', [[<cmd>lua require('telescope.builtin').find_files({find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<CR>]])
  set_keymap('n', '<leader>ff', [[<cmd>lua require('telescope.builtin').find_files()<CR>]])
  set_keymap('n', '<leader>fgr', [[<cmd>lua require('telescope.builtin').live_grep()<CR>]])
  set_keymap('n', '<leader>fg', [[<cmd>lua require('telescope.builtin').git_files()<CR>]])
  set_keymap('n', '<leader>fo', [[<cmd>lua require('telescope.builtin').oldfiles()<CR>]])
  set_keymap('n', '<leader>fi', [[<cmd>lua require('telescope.builtin').file_browser()<CR>]])
  set_keymap('n', '<leader>fst', [[<cmd>lua require('telescope.builtin').grep_string()<CR>]])
  set_keymap('n', '<leader>fb', [[<cmd>lua require('telescope.builtin').current_buffer_fuzzy_find()<CR>]])
  set_keymap('n', '<leader>fh', [[<cmd>lua require('telescope.builtin').help_tags()<CR>]])
  set_keymap('n', '<leader>ft', [[<cmd>lua require('telescope.builtin').tags()<CR>]])
  set_keymap('n', '<leader>fT', [[<cmd>lua require('telescope.builtin').tags{ only_current_buffer = true }<CR>]])
  -- set_keymap('n', '<leader>sf', [[<cmd>lua vim.lsp.buf.formatting()<CR>]])
end

set_up_telescope()
