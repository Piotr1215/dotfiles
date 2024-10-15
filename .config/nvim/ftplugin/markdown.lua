local utils = require "utils"
local vcmd = vim.cmd
-- Function to check if the current file is in the Obsidian repository
local function is_docs_repo()
  -- Get the full path of the current file's directory and normalize it
  local current_file_path = vim.fn.expand "%:p:h"
  local normalized_current_file_path = vim.fn.substitute(current_file_path, "/$", "", "")

  -- Check if the normalized current path is within the specified directories
  return vim.fn.match(normalized_current_file_path, "^/home/decoder/dev/obsidian") ~= -1
    or vim.fn.match(normalized_current_file_path, "^/home/decoder/loft/vcluster-docs") ~= -1
end

-- Setting the text width based on the current file path
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.opt_local.conceallevel = 0

    if is_docs_repo() then
      vim.bo.textwidth = 80
    else
      vim.bo.textwidth = 175
    end
  end,
})

-- this setting makes markdown auto-set the 80 text width limit when typing
-- vcmd('set fo+=a')
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
utils.nmap("<leader>mp", ":MarkdownPreview<CR>:silent !bash -c 'wmctrl -a Firefox'<CR>")

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
  local num_lines = #lines

  if num_lines == 1 then
    -- Single line selection
    local line = lines[1]
    local start_col = start_pos[3]
    local end_col = end_pos[3]
    if vim.fn.mode() == "v" then
      end_col = end_col + 1
    end -- Adjust for visual mode
    lines[1] = line:sub(1, start_col - 1) .. "**" .. line:sub(start_col, end_col) .. "**" .. line:sub(end_col + 1)
  else
    -- Multi-line selection
    lines[1] = lines[1]:sub(1, start_pos[3] - 1) .. "**" .. lines[1]:sub(start_pos[3])
    lines[num_lines] = lines[num_lines]:sub(1, end_pos[3]) .. "**" .. lines[num_lines]:sub(end_pos[3] + 1)
    if vim.fn.mode() == "V" then
      -- For line-wise visual mode, add asterisks at the beginning and end of lines
      lines[1] = "**" .. lines[1]
      lines[num_lines] = lines[num_lines] .. "**"
    end
  end

  vim.api.nvim_buf_set_lines(0, start_pos[2] - 1, end_pos[2], false, lines)
end

-- Set keymaps for both character-wise and line-wise visual modes
vim.api.nvim_buf_set_keymap(0, "v", "<Leader>b", ":lua BoldMe()<CR>", { noremap = true, silent = true })
vim.api.nvim_buf_set_keymap(0, "x", "<Leader>b", ":lua BoldMe()<CR>", { noremap = true, silent = true })

-- Create an autocommand for Markdown files
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "mdx", "mdown", "mkd", "mkdn", "markdown", "mdwn" },
  callback = function()
    -- Safely remove the conflicting Markdown mapping for ']c'
    local status, _ = pcall(function()
      vim.keymap.del("n", "]c", { buffer = true })
    end)
    if not status then
      -- Optional: print or log if needed
      -- print("No such mapping to delete for ']c'")
    end

    -- Remap 'n' mode to jump to the next change (diff jumping) within the buffer
    vim.keymap.set("n", "]c", "]c", { noremap = true, silent = true, buffer = true })
  end,
})
