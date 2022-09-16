require('telescope').setup {
  extensions = {
    fzf = {
      fuzzy = true, -- false will only do exact matching
      override_generic_sorter = true, -- override the generic sorter
      override_file_sorter = true, -- override the file sorter
      case_mode = "smart_case", -- or "ignore_case" or "respect_case"
      -- the default case_mode is "smart_case"
    }
  }
}
require('telescope').load_extension('file_browser')
require('telescope').load_extension('repo')
require('telescope').load_extension('fzf')
require('telescope').load_extension('projects')
require("telescope").load_extension("recent_files")
require("telescope").load_extension("emoji")

local key = vim.api.nvim_set_keymap
local set_up_telescope = function()
  local set_keymap = function(mode, bind, cmd)
    key(mode, bind, cmd, { noremap = true, silent = true })
  end
  set_keymap('n', '<leader><leader>', [[<cmd>lua require('telescope.builtin').buffers()<CR>]])
  --set_keymap('n', '<leader>tf', [[<cmd>lua require('telescope.builtin').find_files({find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<CR>]])
  set_keymap('n', '<leader>fp', [[<cmd>lua require('telescope.builtin').find_files({search_dirs = {"$PWD"}})<CR>]])
  set_keymap('n', '<leader>fpp', [[<cmd>lua require('telescope.builtin').find_files({search_dirs = {"~/dev"}})<CR>]])
  set_keymap('n', '<leader>fr', [[<cmd>lua require'telescope'.extensions.repo.list{search_dirs = {"~/dev"}}<CR>]])
  set_keymap('n', '<leader>fgr', [[<cmd>lua require('telescope.builtin').live_grep()<CR>]])
  set_keymap('n', '<leader>fg', [[<cmd>lua require('telescope.builtin').git_files()<CR>]])
  set_keymap('n', '<leader>fo', [[<cmd>lua require('telescope.builtin').oldfiles()<CR>]])
  set_keymap('n', '<leader>fi', ':Telescope file_browser<CR>')
  set_keymap('n', '<leader>fst', [[<cmd>lua require('telescope.builtin').grep_string({search_dirs = {"~/dev"}})<CR>]])
  set_keymap('n', '<leader>fb', [[<cmd>lua require('telescope.builtin').current_buffer_fuzzy_find()<CR>]])
  set_keymap('n', '<leader>fh', [[<cmd>lua require('telescope.builtin').help_tags()<CR>]])
  set_keymap('n', '<leader>ft', [[<cmd>lua require('telescope.builtin').tagstack()<CR>]])
  set_keymap('n', '<leader>re', [[<cmd>lua require('telescope.builtin').registers()<CR>]])
  set_keymap('n', '<leader>fc', [[<cmd>lua require('telescope.builtin').colorscheme()<CR>]])
  set_keymap('n', '<leader>rf', [[<cmd>lua require('telescope').extensions.recent_files.pick()<CR>]])
  set_keymap('n', '<leader>fT', [[<cmd>lua require('telescope.builtin').tags{ only_current_buffer = true }<CR>]])
  -- set_keymap('n', '<leader>sf', [[<cmd>lua vim.lsp.buf.formatting()<CR>]])
end

set_up_telescope()

