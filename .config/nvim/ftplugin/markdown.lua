local utils = require "utils"
local vcmd = vim.cmd
-- Function to check if the current file is in the Obsidian repository
local function is_in_obsidian_repo()
  local current_file_path = vim.fn.expand "%:p:h"
  -- Replace '/path/to/obsidian/repo' with the actual path to your Obsidian repository
  return string.find(current_file_path, "/home/decoder/dev/obsidian/") ~= nil
end
vcmd "set conceallevel=0"

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.opt_local.conceallevel = 0
  end,
})

-- this setting makes markdown auto-set the 80 text width limit when typing
-- vcmd('set fo+=a')
if is_in_obsidian_repo() then
  vim.bo.textwidth = 175 -- No limit for Obsidian repository
else
  vim.bo.textwidth = 80 -- Limit to 80 for other repositories
end
vcmd "setlocal spell spelllang=en_us"
vcmd "setlocal expandtab shiftwidth=4 softtabstop=4 autoindent"

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
  vim.cmd "call search('```', 'cb')"
  if outside then
    vim.cmd "normal! Vo"
  else
    vim.cmd "normal! j0Vo"
  end
  vim.cmd "call search('```')"
  if not outside then
    vim.cmd "normal! k"
  end
end

utils.omap("am", "<Cmd>lua MarkdownCodeBlock(true)<CR>")
utils.xmap("am", "<Cmd>lua MarkdownCodeBlock(true)<CR>")
utils.omap("im", "<Cmd>lua MarkdownCodeBlock(false)<CR>")
utils.xmap("im", "<Cmd>lua MarkdownCodeBlock(false)<CR>")
-- utils.nmap("<nop>", "<Plug>Markdown_Fold") -- tab is for moving around only
utils.nmap("<Tab>", "<Plug>Markdown_Fold") -- tab is for moving around only
utils.nmap("]]", "<Plug>Markdown_MoveToNextHeader") -- tab is for moving around only;
utils.nmap("[[", "<Plug>Markdown_MoveToPreviousHeader") -- tab is for moving around only
utils.lnmap("ctd", "4wvg$y") -- copy description from the taskwarrior task in the markdown format
utils.vmap("<leader>hi", ":HeaderIncrease<CR>") -- increase header level

-- Makrdown.nvim settings
vim.g.vim_markdown_folding_disabled = 0
vim.g.vim_markdown_folding_style_pythonic = 1
vim.g.vim_markdown_folding_level = 2
vim.g.vim_markdown_toc_autofit = 1
vim.g.vim_markdown_conceal = 0
vim.g.vim_markdown_conceal_code_blocks = 0
vim.g.vim_markdown_no_extensions_in_markdown = 1
vim.g.vim_markdown_autowrite = 1
vim.g.vim_markdown_follow_anchor = 1
vim.g.vim_markdown_auto_insert_bullets = 0
vim.g.vim_markdown_new_list_item_indent = 0

-- MarkdownPreview settings
vim.g.mkdp_browser = "/usr/bin/firefox"
vim.g.mkdp_echo_preview_url = 0
utils.nmap("<leader>mp", ":MarkdownPreview<CR>")

-- MarkdownClipboardImage settings
utils.nmap("<leader>pi", ":call mdip#MarkdownClipboardImage()<CR>")

vim.api.nvim_buf_set_keymap(0, "v", ",wl", [[c[<c-r>"]()<esc>]], { noremap = false })

-- Setup cmp setup buffer configuration - 👻 text off for markdown
local cmp = require "cmp"
cmp.setup.buffer {
  sources = {
    { name = "vsnip" },
    { name = "projects" },
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
  local start_pos = vim.fn.getpos "'<"
  local end_pos = vim.fn.getpos "'>"
  local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
  lines[1] = lines[1]:sub(1, start_pos[3] - 1) .. "**" .. lines[1]:sub(start_pos[3])
  lines[#lines] = lines[#lines]:sub(1, end_pos[3]) .. "**" .. lines[#lines]:sub(end_pos[3] + 1)
  vim.api.nvim_buf_set_lines(0, start_pos[2] - 1, end_pos[2], false, lines)
end

vim.api.nvim_buf_set_keymap(0, "v", "<Leader>b", ":lua BoldMe()<CR>", { noremap = true, silent = true })
