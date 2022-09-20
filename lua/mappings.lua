vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Helper Functions {{{
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local opts = { noremap = true, silent = true }

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
vim.api.nvim_set_keymap('n', 'k', "v:count == 0 ? 'gk' : 'k'", { noremap = true, expr = true, silent = true })
vim.api.nvim_set_keymap('n', 'j', "v:count == 0 ? 'gj' : 'j'", { noremap = true, expr = true, silent = true })
vim.keymap.set("n", "<C-j>", [[:keepjumps normal! j}k<cr>]], { noremap = true, silent = true })
vim.keymap.set("n", "<C-k>", [[:keepjumps normal! k{j<cr>]], { noremap = true, silent = true })
vim.keymap.set("n", "<Leader>ts", "<cmd>Telescope<cr>", opts)

-- MOVE AROUND --
lnmap("tkf", ":lua require('telekasten').find_notes()<CR>") -- Move Line Up in Normal Mode
nmap("<BS>", "^")
nmap("<C-f>", ":Pretty<CR>")
vmap("<S-PageDown>", ":m '>+1<CR>gv=gv") -- Move Line Down in Visual Mode
vmap("<S-PageUp>", ":m '<-2<CR>gv=gv") -- Move Line Up in Visual Mode
nmap("<leader>k", ":m .-2<CR>==") -- Move Line Up in Normal Mode
nmap("<leader>j", ":m .+1<CR>==") -- Move Line Down in Normal Mode

-- SEARCH & REPLACE --
nmap("<Leader>em", ":/\\V\\c\\<\\>") -- find exact match
-- Easy Motion Mappings
emap("<Leader>o", "<Plug>(easymotion-prefix)")
emap("<Leader>of", "<Plug>(easymotion-bd-f)")
emap("<Leader>ol", "<Plug>(easymotion-bd-w)")
emap("<Leader>oo", "<Plug>(easymotion-overwin-f2)")
-- Stop search highlight
nmap(",<space>", ":nohlsearch<CR>")
vmap("<C-r>", '"hy:%s/<C-r>h//gc<left><left><left>')
vmap("//", 'y/\\V<C-R>=escape(@",\'/\')<CR><CR>')
-- Search only in visual selection using %V atom
vmap("<C-s>", ":s/\\%V")

-- MACROS --
nmap("<Leader>q", "@q")
xmap("Q", ":'<,'>:normal @q<CR>")
lnmap("jq", ":g/{/.!jq .<CR>")
tmap("<ESC>", "<C-\\><C-n>")
xmap("<leader>ee", "vamy}o^[PO** Results **^[jjvim:@*!bash")

-- MANIPULATE TEXT --
-- Copy & Paste
xmap("<leader>p", "\"_dP") -- paste the same yanked text into visual selection
nmap("S", "\"_diwP") -- substitute current word with last yanked text
vmap("F", "\"_dP") -- substitute selection with last yanked text
lnmap("cpf", ":let @+ = expand(\"%:t\")<cr>") -- Copy current file name
nmap("gp", "`[v`]") -- select last pasted text
nmap("<leader>2", '"*p') -- paste from * (selection register)
vmap("<C-c>", '"+y') -- copy selection to clipboard with ctrl+c
nmap('<leader>yw', '"+yiw') -- copy word under cusror to the clipboard buffer
nmap('Y', 'yg_') -- copies till the end of a line without a new line, fits with shift + d, c etc
nmap('<leader>y', '"+y$') -- copy from cursor to end of line
nmap('yaf', '[m{jv]m%y') -- copy function or routine body and keyword
-- black hole register operations
lnmap('d', '"_D')
lnmap('diw', '"_diw')
lnmap('daw', '"_daw')
lnmap('diW', '"_diW')
lnmap('dd', '"_dd')
-- useful for passing over braces and quotations
imap("<C-l>", "<C-o>a")
-- comment paragraphs
nmap("<silent> <leader>c}", "v}:call nerdcomment('x', 'toggle')<cr>")
nmap("<silent> <leader>c{", "v{:call nerdcomment('x', 'toggle')<cr>")
-- insert 2 empty lines and go into inser mode
nmap("<leader>L", "O<ESC>O")
nmap("<leader>l", "o<cr>")
-- add line below without entering insert mode!
nmap("<leader><Up>", ':<c-u>put!=repeat([\'\'],v:count)<bar>\']+1<cr>')
nmap("<leader><Down>", ':<c-u>put =repeat([\'\'],v:count)<bar>\'[-1<cr>')
-- removes whitespace
nmap('<leader>rspace', ':%s/\\s\\+$//e')
-- insert space
nmap('<leader>i', 'i<space><esc>')
-- delete word forward in insert mode
nmap('<leader>i', 'i<space><esc>')
-- delete word with ctrl backspace
imap('<C-BS>', '<C-W>')
-- replace multiple words simultaniously
nmap('<leader>x', '*``cgn')
nmap('<leader>X', '#``cgn')
-- cut and copy content to next header #
nmap('cO', ':.,/^#/-1d<cr>')
nmap('cY', ':.,/^#/-1y<cr>')
-- split line in two
nmap('<leader>sp', 'i<cr><esc>')
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

-- Startify
lnmap("st", ":Startify<CR>") -- start Startify screen
