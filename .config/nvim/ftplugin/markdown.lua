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
