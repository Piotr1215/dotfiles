local utils = require('utils')
local vcmd = vim.cmd

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

vcmd('set conceallevel=0')
vcmd('setlocal spell spelllang=en_us')
vcmd('setlocal expandtab shiftwidth=4 softtabstop=4 autoindent')

-- MarkdownPreview settings
vim.g.mkdp_browser = '/usr/bin/firefox'
vim.g.mkdp_echo_preview_url = 0

utils.nmap("nmap <buffer><silent> <leader>ps", ":call mdip#MarkdownClipboardImage()<CR>")

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
