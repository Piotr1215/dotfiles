local utils = require('utils')
local vcmd = vim.cmd
-- Function to check if the current file is in the Obsidian repository
local function is_in_obsidian_repo()
  local current_file_path = vim.fn.expand('%:p:h')
  -- Replace '/path/to/obsidian/repo' with the actual path to your Obsidian repository
  return string.find(current_file_path, '/home/decoder/dev/obsidian/') ~= nil
end
vcmd('set conceallevel=0')
-- this setting makes markdown auto-set the 80 text width limit when typing
-- vcmd('set fo+=a')
if is_in_obsidian_repo() then
  vim.bo.textwidth = 250 -- No limit for Obsidian repository
else
  vim.bo.textwidth = 80  -- Limit to 80 for other repositories
end
vcmd('setlocal spell spelllang=en_us')
vcmd('setlocal expandtab shiftwidth=4 softtabstop=4 autoindent')

vim.api.nvim_exec(
  [[
" arrows
iabbrev >> →
iabbrev << ←
iabbrev ^^ ↑
iabbrev VV ↓
]],
  false
)

-- Operations on Fenced Code Block
function MarkdownCodeBlock(outside)
  vim.cmd("call search('```', 'cb')")
  if outside then
    vim.cmd("normal! Vo")
  else
    vim.cmd("normal! j0Vo")
  end
  vim.cmd("call search('```')")
  if not outside then
    vim.cmd("normal! k")
  end
end

utils.omap('am', '<Cmd>lua MarkdownCodeBlock(true)<CR>')
utils.xmap('am', '<Cmd>lua MarkdownCodeBlock(true)<CR>')
utils.omap('im', '<Cmd>lua MarkdownCodeBlock(false)<CR>')
utils.xmap('im', '<Cmd>lua MarkdownCodeBlock(false)<CR>')
utils.nmap("<nop>", "<Plug>Markdown_Fold")               -- tab is for moving around only
utils.lnmap("nh", "<Plug>Markdown_MoveToNextHeader")     -- tab is for moving around only
utils.lnmap("ph", "<Plug>Markdown_MoveToPreviousHeader") -- tab is for moving around only
utils.lnmap("ctd", "4wvg$y")                             -- copy description from the taskwarrior task in the markdown format
-- cut and copy content to next header #
utils.nmap("cO", ":.,/^#/-1d<cr>")
utils.nmap("cY", ":.,/^#/-1y<cr>")

-- MarkdownPreview settings
vim.g.mkdp_browser = '/usr/bin/firefox'
vim.g.mkdp_echo_preview_url = 0
utils.nmap('<leader>mp', ':MarkdownPreview<CR>')

-- MarkdownClipboardImage settings
utils.nmap("<leader>pi", ":call mdip#MarkdownClipboardImage()<CR>")

vim.api.nvim_buf_set_keymap(0, "v", ",wl", [[c[<c-r>"]()<esc>]], { noremap = false })

-- Setup cmp setup buffer configuration - 👻 text off for markdown
local cmp = require "cmp"
cmp.setup.buffer {
  sources = {
    { name = "vsnip" },
    { name = "spell" },
    {
      name = "buffer",
      option = {
        get_bufnrs = function()
          local bufs = {}
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            bufs[vim.api.nvim_win_get_buf(win)] = true
          end
          return vim.tbl_keys(bufs)
        end,
      },
    },
    { name = "path" },
  },
  experimental = {
    ghost_text = false,
  },
}

function BoldMe()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]
  local start_col = start_pos[3]
  local end_col = end_pos[3]

  if end_line == start_line then
    local line = vim.api.nvim_buf_get_lines(0, start_line - 1, start_line, false)[1]
    local modified_line = line:sub(1, start_col - 1) ..
        '**' .. line:sub(start_col, end_col) .. '**' .. line:sub(end_col + 1)
    vim.api.nvim_buf_set_lines(0, start_line - 1, start_line, false, { modified_line })
  else
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    lines[1] = lines[1]:sub(1, start_col - 1) .. '**' .. lines[1]:sub(start_col)
    lines[#lines] = lines[#lines]:sub(1, end_col) .. '**' .. lines[#lines]:sub(end_col + 1)
    vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, lines)
  end
end

vim.api.nvim_buf_set_keymap(0, 'v', '<Leader>b', ':lua BoldMe()<CR>', { noremap = true, silent = true })
