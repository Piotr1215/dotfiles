local utils = require('utils')
local vcmd = vim.cmd

vcmd('set conceallevel=0')
-- this setting makes markdown auto-set the 80 text width limit when typing
-- vcmd('set fo+=a')
vcmd('set textwidth=80')
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

-- MarkdownPreview settings
vim.g.mkdp_browser = '/usr/bin/firefox'
vim.g.mkdp_echo_preview_url = 0
utils.nmap('<leader>mp', ':MarkdownPreview<CR>')

-- MarkdownClipboardImage settings
utils.nmap("<leader>mm", ":call mdip#MarkdownClipboardImage()<CR>")

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
