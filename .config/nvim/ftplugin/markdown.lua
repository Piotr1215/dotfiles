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

-- Operations on Code Block
vim.cmd(
  [[
     function! MarkdownCodeBlock(outside)
         call search('```', 'cb')
         if a:outside
             normal! Vo
         else
             normal! j0Vo
         endif
         call search('```')
         if ! a:outside
             normal! k
         endif
     endfunction
     ]])
utils.omap('am', ':call MarkdownCodeBlock(1)<cr>')
utils.xmap('am', ':call MarkdownCodeBlock(1)<cr>')
utils.omap('im', ':call MarkdownCodeBlock(0)<cr>')
utils.xmap('im', ':call MarkdownCodeBlock(0)<cr>')

-- MarkdownPreview settings
vim.g.mkdp_browser = '/usr/bin/firefox'
vim.g.mkdp_echo_preview_url = 0

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
