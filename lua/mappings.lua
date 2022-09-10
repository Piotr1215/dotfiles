vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Helper Functions {{{
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local sysname = vim.loop.os_uname().sysname

local function map(mode, shortcut, command)
  vim.api.nvim_set_keymap(mode, shortcut, command, { noremap = true, silent = true })
end

local function emap(shortcut, command)
  map('', shortcut, command)
end

--Leader normal mapping
local function lnmap(shortcut, command)
  local leader = "<leader>" .. shortcut
  map('n', leader, command)
end

local function nmap(shortcut, command)
  map('n', shortcut, command)
end

local function imap(shortcut, command)
  map('i', shortcut, command)
end

local function vmap(shortcut, command)
  map('v', shortcut, command)
end

local function xmap(shortcut, command)
  map('x', shortcut, command)
end

local function omap(shortcut, command)
  map('o', shortcut, command)
end

local function smap(shortcut, command)
  map('s', shortcut, command)
end

local function tmap(shortcut, command)
  map('t', shortcut, command)
end

-- }}}
-- Map only if Linux
vim.api.nvim_set_keymap('n', 'k', "v:count == 0 ? 'gk' : 'k'", { noremap = true, expr = true, silent = true })
vim.api.nvim_set_keymap('n', 'j', "v:count == 0 ? 'gj' : 'j'", { noremap = true, expr = true, silent = true })
vim.keymap.set("n", "<C-j>", [[:keepjumps normal! j}k<cr>]], { noremap = true, silent = true })
vim.keymap.set("n", "<C-k>", [[:keepjumps normal! k{j<cr>]], { noremap = true, silent = true })
local opts = { noremap = true, silent = true }
vim.keymap.set("n", "<Leader><Leader>i", "<cmd>PickIcons<cr>", opts)
vim.keymap.set("n", "<Leader>ts", "<cmd>Telescope<cr>", opts)
vim.keymap.set("i", "<C-9>", "]", opts)
vim.keymap.set("i", "<C-8>", "[", opts)
vim.keymap.set("n", "<C-9>", "]", opts)
vim.keymap.set("n", "<C-8>", "[", opts)
vim.keymap.set("i", "<C-i>", "<cmd>PickIconsInsert<cr>", opts)
vim.keymap.set("i", "<A-i>", "<cmd>PickAltFontAndSymbolsInsert<cr>", opts)
if sysname == 'Linux' then
  nmap('ö', '/')
  imap('ö', '/')
end
-- MOVE AROUND --
lnmap("tkf", ":lua require('telekasten').find_notes()<CR>") -- Move Line Up in Normal Mode
nmap("<BS>", "^")
nmap("<C-f>", ":Pretty<CR>")
vmap("<S-PageDown>", ":m '>+1<CR>gv=gv") -- Move Line Down in Visual Mode
vmap("<S-PageUp>", ":m '<-2<CR>gv=gv") -- Move Line Up in Visual Mode
nmap("<leader>k", ":m .-2<CR>==") -- Move Line Up in Normal Mode
nmap("<leader>j", ":m .+1<CR>==") -- Move Line Down in Normal Mode
nmap("<Leader>nh", ":.,/^#/<CR>") -- Got to next markdown header
nmap("<Leader>em", ":/\\V\\c\\<\\>") -- find exact match
imap("<C-l>", "<C-o>A") -- useful for passing over braces and quotations

-- SEARCH & REPLACE --
-- Easy Motion Mappings
emap("<Leader>o", "<Plug>(easymotion-prefix)")
emap("<Leader>of", "<Plug>(easymotion-bd-f)")
emap("<Leader>ol", "<Plug>(easymotion-bd-w)")
emap("<Leader>oo", "<Plug>(easymotion-overwin-f2)")
-- Stop search highlight
nmap(",<space>", ":nohlsearch<CR>")
vmap("<C-r>", '"hy:%s/<C-r>h//gc<left><left><left>')
vmap("//", 'y/\\V<C-R>=escape(@",\'/\')<CR><CR>')
-- nmap(";;", ":%s:::g<Left><Left><Left>")
-- nmap(";'", ":%s:::cg<Left><Left><Left><Left>")

-- MACROS --
nmap("<Leader>q", "@q")
xmap("Q", ":'<,'>:normal @q<CR>")
lnmap("jq", ":g/{/.!jq .<CR>")
tmap("<ESC>", "<C-\\><C-n>")

-- MANIPULATE TEXT --
-- Copy file name
lnmap("cpf", ":let @* = expand(\"%:t\")<CR>")
-- Comment paragraphs
nmap("<silent> <leader>c}", "V}:call NERDComment('x', 'toggle')<CR>")
nmap("<silent> <leader>c{", "V{:call NERDComment('x', 'toggle')<CR>")
-- Insert 2 empty lines and go into inser mode
nmap("<leader>fe", "<Plug>(grammaruos-fixit)")
nmap("<leader>fa", "<Plug>(grammaruos-fixall)")
nmap("<leader>L", "O<ESC>O")
nmap("<leader>l", "o<cr>")
-- Select last pasted text
nmap("gp", "`[v`]")
-- Add line below without entering insert mode!
nmap("<leader><Up>", ':<c-u>put!=repeat([\'\'],v:count)<bar>\']+1<cr>')
nmap("<leader><Down>", ':<c-u>put =repeat([\'\'],v:count)<bar>\'[-1<cr>')
-- Paste crom clipboard
nmap("<leader>2", '"*p')
-- Copy selection to clipboard with Ctrl+c
vmap("<C-c>", '"*y')
-- Copy word under cusror to the clipboard buffer
nmap('<leader>yw', '"*yiw')
-- Removes whitespace
nmap('<Leader>rspace', ':%s/\\s\\+$//e')
-- Removes empty lines if there are more than 2
nmap('<Leader>rlines', ':%s/\\n\\{3,}/\\r\\r/e')
-- Insert space
nmap('<Leader>i', 'i<space><esc>')
-- delete word forward in insert mode
nmap('<Leader>i', 'i<space><esc>')
-- black hole register operations
lnmap('d', '"_D')
lnmap('diw', '"_diw')
lnmap('daw', '"_daw')
lnmap('diW', '"_diW')
lnmap('dd', '"_dd')
-- delete word with Ctrl Backspace
imap('<C-BS>', '<C-W>')
-- Copies till the end of a line. Fits with Shift + D, C etc
nmap('Y', 'yg_')
-- Replace multiple words simultaniously
-- Repeat, with .
nmap('<Leader>x', '*``cgn')
nmap('<Leader>X', '#``cgN')
-- Copy from cursor to end of line
nmap('<leader>y', '"+y$')
-- cut and copy content to next header #
nmap('cO', ':.,/^#/-1d<CR>')
nmap('cY', ':.,/^#/-1y<CR>')
-- Split line in two
nmap('<Leader>sp', 'i<CR><Esc>')
-- Copy function or routine body and keyword
nmap('yaf', '[m{jV]m%y')
nmap('<leader>wi', ':setlocal textwidth=80<cr>')
vim.cmd(
  [[
     function! s:check_back_space() abort
       let col = col('.') - 1
       return !col || getline('.')[col - 1]  =~# '\s'
     endfunction
     ]])

-- MARKDOWN --
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
omap('am', ':call MarkdownCodeBlock(1)<cr>')
xmap('am', ':call MarkdownCodeBlock(1)<cr>')
omap('im', ':call MarkdownCodeBlock(0)<cr>')
xmap('im', ':call MarkdownCodeBlock(0)<cr>')
-- Markdown Previev
nmap('<leader>mp', ':MarkdownPreview<CR>')
-- Fix Markdown Errors
nmap('<leader>fx', ':<C-u>CocCommand markdownlint.fixAll<CR>')
nmap('<leader>fmt', ':Pretty<CR>')
--" Markdown paste image

-- EXTERNAL --
-- Execute line under cursor in shell
nmap('<leader>ex', ':exec \'!\'.getline(\'.\')<CR>')
-- Set spellcheck on/off
nmap('<Leader>son', ':setlocal spell spelllang=en_us<CR>')
nmap('<Leader>sof', ':set nospell<CR>')
-- Accept first grammar correction
nmap('<Leader>c', '1z=')
-- Upload selected to ix.io
vmap('<Leader>pp', ':w !curl -F "f:1=<--- ix.io<CR>')
-- setup mapping to call :LazyGit
nmap('<leader>gg', ':LazyGit<CR>')

-- NAVIGATION --
-- Nvim Tree settings
nmap('<leader>df', ':NvimTreeToggle<CR>')
nmap('<Leader>da', ':NvimTreeFindFile<CR>')
-- Save buffer
nmap('<leader>w', ':w<CR>')
-- Move screen to contain current line at the top
--local pathToVimInit = ':source ' .. vim.fn.expand('~/.config/nvim/init.vim<CR>')
nmap('<leader>sv', ':source /home/decoder/.config/nvim/init.lua<CR>')
--nmap('<leader>sv', pathToVimInit)
-- jj in insert mode instead of ESC
imap('jj', '<Esc>')
imap('jk', '<Esc>')
-- Zoom split windows
nmap('Zz', '<c-w>_ | <c-w>|')
nmap('Zo', '<c-w>=')
-- Floatterm settings
nmap('<Leader>fs', ':FloatermShow<CR>')
nmap('<Leader>fh', ':FloatermHide<CR>')
nmap('<Leader>fn', ':FloatermNext<CR>')
nmap('<Leader>fc', ':FloatermKill<CR>')

-- PROGRAMMING --
-- Use `[g` and `]g` to navigate diagnostics
-- Apply AutoFix to problem on the current line.
-- Map function and class text objects
-- NOTE: Requires 'textDocument.documentSymbol' support from the language server.
xmap('if', '<Plug>(coc-funcobj-i)')
omap('if', '<Plug>(coc-funcobj-i)')
xmap('af', '<Plug>(coc-funcobj-a)')
omap('af', '<Plug>(coc-funcobj-a)')
-- Use CTRL-S for selections ranges.
-- Requires 'textDocument/selectionRange' support of language server.
nmap('<silent>', '<C-s> <Plug>(coc-range-select)')
xmap('<silent>', '<C-s> <Plug>(coc-range-select)')
-- vsnip settings
-- Expand
imap('<expr>', '<C-j>   vsnip#expandable()  ? \'<Plug>(vsnip-expand)\'         : \'<C-j>')
smap('<expr>', '<C-j>   vsnip#expandable()  ? \'<Plug>(vsnip-expand)\'         : \'<C-j>')

-- Expand or jump
imap('<expr>', '<C-l>   vsnip#available(1)  ? \'<Plug>(vsnip-expand-or-jump)\' : \'<C-l>')
smap('<expr>', '<C-l>   vsnip#available(1)  ? \'<Plug>(vsnip-expand-or-jump)\' : \'<C-l>')
-- Select or cut text to use as $TM_SELECTED_TEXT in the next snippet.
-- See https://github.com/hrsh7th/vim-vsnip/pull/50
nmap('<leader>t', '<Plug>(vsnip-select-text)')
xmap('<leader>t', '<Plug>(vsnip-select-text)')
nmap('<leader>tc', '<Plug>(vsnip-cut-text)')
xmap('<leader>tc', '<Plug>(vsnip-cut-text)')

-- Abbreviations
vim.cmd('abb cros Crossplane')
-- Telekasten
nmap('<leader>tk', ':lua require(\'telekasten\').panel()<CR>')

-- Ranger
tmap("<M-i>", "<C-\\><C-n>:RnvimrResize<CR>")
nmap("<M-o>", ":RnvimrToggle<CR>")
tmap("<M-o>", "<C-\\><C-n>:RnvimrToggle<CR>")

-- Harpoon
nmap("<leader>ha", ":lua require(\"harpoon.mark\").add_file()<CR>")
nmap("<leader>hm", ":lua require(\"harpoon.ui\").toggle_quick_menu()<CR>")
nmap("<leader>hh", ":lua require(\"harpoon.ui\").nav_next()<CR>")
nmap("<leader>hl", ":lua require(\"harpoon.ui\").nav_prev()<CR>")

-- Mdeval
vim.api.nvim_set_keymap('n', '<leader>ev',
  "<cmd>lua require 'mdeval'.eval_code_block()<CR>",
  { silent = true, noremap = true })
