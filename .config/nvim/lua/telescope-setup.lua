local t = require("telescope")
local builtin = require("telescope.builtin")
local z_utils = require("telescope._extensions.zoxide.utils")

require('telescope').load_extension('file_browser')
require('telescope').load_extension('repo')
require('telescope').load_extension('fzf')
require("telescope").load_extension("emoji")
require('telescope').load_extension('bookmarks')
require("telescope").load_extension('zoxide')
require('telescope').load_extension('tmuxinator')
require("telescope").load_extension("live_grep_args")
require("telescope").load_extension('cmdline')

require('telescope').setup {
  defaults = {
    vimgrep_arguments = {
      'rg',
      '--color=never',
      '--no-heading',
      '--with-filename',
      '--line-number',
      '--column',
      '--smart-case',
      '--hidden',
    },
  },
  extensions = {
    fzf = {
      fuzzy = true,                   -- false will only do exact matching
      override_generic_sorter = true, -- override the generic sorter
      override_file_sorter = true,    -- override the file sorter
      case_mode = "smart_case",       -- or "ignore_case" or "respect_case"
    },
    file_browser = {
      hidden = true,
    },
    emoji = {
      action = function(emoji)
        vim.fn.setreg("*", emoji.value)
        print([[Press p or "*p to paste this emoji]] .. emoji.value)
        -- insert emoji when picked
        vim.api.nvim_put({ emoji.value }, 'c', false, true)
      end,
    },
    zoxide = {
      prompt_title = "[ Zoxide List ]",
      -- Zoxide list command with score
      list_command = "zoxide query -ls",
      mappings = {
        default = {
          keepinsert = true,
          action = function(selection)
            builtin.find_files({ cwd = selection.path, find_command = { 'rg', '--files', '--hidden', '-g', '!.git' } })
            -- builtin.find_files({ cwd = selection.path })
          end,
        },
        ["<C-s>"] = { action = z_utils.create_basic_command("split") },
        ["<C-v>"] = { action = z_utils.create_basic_command("vsplit") },
        ["<C-e>"] = { action = z_utils.create_basic_command("edit") },
        ["<C-b>"] = {
          keepinsert = true,
          action = function(selection)
            builtin.file_browser({ cwd = selection.path })
          end
        },
        ["<C-f>"] = {
          keepinsert = true,
          action = function(selection)
            builtin.find_files({ cwd = selection.path, find_command = { 'rg', '--files', '--hidden', '-g', '!.git' } })
          end
        }
      }
    },
  }
}

-- Load the extension
t.load_extension('zoxide')

-- Configure find files builtin with custom opts
-- For neovim's config directory
function search_dev()
  local opts = {
    prompt_title = "Dev",                                 -- Title for the picker
    shorten_path = false,                                 -- Display full paths, short paths are ugly
    cwd = "~/dev",                                        -- Set path to directory whose files should be shown
    file_ignore_patterns = { ".git", ".png", "tags" },    -- Folder/files to be ignored
    initial_mode = "insert",                              -- Start in insert mode
    selection_strategy = "reset",                         -- Start selection from top when list changes
    theme = require("telescope.themes").get_dropdown({}), -- Theme to be used, can be omitted to use defaults
  }

  -- Pass opts to find_files
  require("telescope.builtin").find_files(opts)
end

local default_opts = { noremap = true, silent = true }
vim.api.nvim_set_keymap('v', '<leader>fsd',
  'y<ESC>:Telescope live_grep_args default_text="<c-r>0<CR>a" /home/decoder/dev"', default_opts)
vim.api.nvim_set_keymap('v', '<leader>fs', 'y<ESC>:Telescope live_grep default_text=<c-r>0<CR> search_dirs={"$PWD"}',
  default_opts)
vim.api.nvim_set_keymap('n', "<leader>tm", ":lua require('telescope').extensions.tmuxinator.projects{}<CR>", default_opts)

local key = vim.api.nvim_set_keymap
local set_up_telescope = function()
  local set_keymap = function(mode, bind, cmd)
    key(mode, bind, cmd, { noremap = true, silent = true })
  end
  set_keymap("n", "<Leader>fd", "<cmd>lua search_dev()<CR>")
  set_keymap('n', '<leader><leader>', [[<cmd>lua require('telescope.builtin').buffers()<CR>]])
  set_keymap('n', '<leader>ff',
    [[<cmd>cd %:p:h<CR><cmd>pwd<CR><cmd>lua require('telescope.builtin').find_files({find_command = {'rg', '--files', '--hidden', '-g', '!.git' }, {search_dirs = {"$PWD"}}})<CR>]])
  set_keymap('n', '<leader>fr', [[<cmd>lua require'telescope'.extensions.repo.list{search_dirs = {"~/dev"}}<CR>]])
  set_keymap('n', '<leader>fw', [[<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>]])
  set_keymap('n', '<leader>fg', [[<cmd>lua require('telescope.builtin').git_files()<CR>]])
  set_keymap('n', '<leader>fo', [[<cmd>lua require('telescope.builtin').oldfiles()<CR>]])
  set_keymap('n', '<leader>fi', ':Telescope file_browser hidden=true<CR>')
  set_keymap('i', '<C-e>', '<cmd>:Telescope symbols<CR>')
  set_keymap('n', '<leader>fe', [[<cmd>Telescope emoji<CR>]])
  set_keymap('n', '<leader>fsw', [[<cmd>lua require('telescope.builtin').grep_string({search_dirs = {"~/dev"}})<CR>]])
  set_keymap('n', '<leader>fb', [[<cmd>lua require('telescope.builtin').current_buffer_fuzzy_find()<CR>]])
  set_keymap('n', '<leader>fh', [[<cmd>lua require('telescope.builtin').search_history()<CR>]])
  set_keymap('n', '<leader>ds', [[<cmd>lua require('telescope.builtin').lsp_document_symbols()<CR>]])
  set_keymap('n', '<leader>gj', [[<cmd>lua require('telescope.builtin').jumplist()<CR>]])
  set_keymap('n', '<leader>re', [[<cmd>lua require('telescope.builtin').registers()<CR>]])
  set_keymap('n', '<leader>fc', [[<cmd>lua require('telescope.builtin').colorscheme()<CR>]])
  set_keymap('n', '<leader>fz', [[<cmd>lua require('telescope').extensions.zoxide.list()<CR>]])
  set_keymap('n', '<leader>ft', ':TodoTelescope<CR>')
  set_keymap('n', '<leader>rg', [[<cmd>lua require('telescope.builtin').registers()<CR>]])
  set_keymap('v', '<leader>rg', [["_d <cmd>lua require('telescope.builtin').registers()<CR>]])
  set_keymap('n', '<leader>?', [[<cmd>lua require('telescope.builtin').help_tags()<CR>]])
end

set_up_telescope()
