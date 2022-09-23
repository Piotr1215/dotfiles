local utils = require('utils')
local opts = { noremap = true, silent = true }

vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- MOVE AROUND --
-- j/k moves over virtual (wrapped) lines
vim.api.nvim_set_keymap('n', 'k', "v:count == 0 ? 'gk' : 'k'", { noremap = true, expr = true, silent = true })
vim.api.nvim_set_keymap('n', 'j', "v:count == 0 ? 'gj' : 'j'", { noremap = true, expr = true, silent = true })
-- Navigate between paragraphs and add to jumplist
vim.keymap.set("n", "<C-j>", [[:keepjumps normal! j}k<cr>]], opts)
vim.keymap.set("n", "<C-k>", [[:keepjumps normal! k{j<cr>]], opts)
vim.keymap.set("n", "<Leader>ts", "<cmd>Telescope<cr>", opts)

-- MOVE AROUND --
utils.lnmap("tkf", ":lua require('telekasten').find_notes()<CR>") -- Move Line Up in Normal Mode
utils.nmap("<BS>", "^")
utils.nmap("<C-f>", ":Pretty<CR>")
utils.vmap("<S-PageDown>", ":m '>+1<CR>gv=gv") -- Move Line Down in Visual Mode
utils.vmap("<S-PageUp>", ":m '<-2<CR>gv=gv") -- Move Line Up in Visual Mode
utils.nmap("<leader>k", ":m .-2<CR>==") -- Move Line Up in Normal Mode
utils.nmap("<leader>j", ":m .+1<CR>==") -- Move Line Down in Normal Mode

-- SEARCH & REPLACE --
utils.nmap("<Leader>em", ":/\\V\\c\\<\\>") -- find exact match
-- Easy Motion Mappings
utils.emap("<Leader>o", "<Plug>(easymotion-prefix)")
utils.emap("<Leader>of", "<Plug>(easymotion-bd-f)")
utils.emap("<Leader>ol", "<Plug>(easymotion-bd-w)")
utils.emap("<Leader>oo", "<Plug>(easymotion-overwin-f2)")
-- Stop search highlight
utils.nmap(",<space>", ":nohlsearch<CR>")
utils.vmap("<C-r>", '"hy:%s/<C-r>h//gc<left><left><left>')
utils.vmap("//", 'y/\\V<C-R>=escape(@",\'/\')<CR><CR>')
-- Search only in visual selection using %V atom
utils.vmap("<C-s>", ":s/\\%V")

-- MACROS --
utils.nmap("<Leader>q", "@q")
utils.xmap("Q", ":'<,'>:normal @q<CR>")
utils.lnmap("jq", ":g/{/.!jq .<CR>")
utils.tmap("<ESC>", "<C-\\><C-n>")
utils.xmap("<leader>ee", "vamy}o^[PO** Results **^[jjvim:@*!bash")

-- MANIPULATE TEXT --
-- Copy & Paste
utils.xmap("<leader>p", "\"_dP") -- paste the same yanked text into visual selection
utils.nmap("<leader>sw", "\"_diwP") -- substitute current word with last yanked text
utils.nmap("<leader>sW", "\"_diWP") -- substitute current WORD with last yanked text
utils.vmap("<leader>ss", "\"_dP") -- substitute selection with last yanked text
utils.lnmap("cpf", ":let @+ = expand(\"%:t\")<cr>") -- Copy current file name
utils.nmap("gp", "`[v`]") -- select last pasted text
utils.nmap("<leader>1", '"0p') -- paste from 0 (latest yank)
utils.nmap("<leader>2", '"*p') -- paste from * (selection register)
utils.vmap("<C-c>", '"+y') -- copy selection to clipboard with ctrl+c
utils.nmap('<leader>yw', '"+yiw') -- copy word under cusror to the clipboard buffer
utils.nmap('Y', 'yg_') -- copies till the end of a line without a new line, fits with shift + d, c etc
utils.nmap('<leader>y', '"+y$') -- copy from cursor to end of line
utils.nmap('yaf', '[m{jv]m%y') -- copy function or routine body and keyword
-- black hole register operations
utils.lnmap('d', '"_D')
utils.lnmap('diw', '"_diw')
utils.lnmap('daw', '"_daw')
utils.lnmap('diW', '"_diW')
utils.lnmap('dd', '"_dd')
-- useful for passing over braces and quotations
utils.imap("<C-l>", "<C-o>a")
-- comment paragraphs
utils.nmap("<silent> <leader>c}", "v}:call nerdcomment('x', 'toggle')<cr>")
utils.nmap("<silent> <leader>c{", "v{:call nerdcomment('x', 'toggle')<cr>")
-- insert 2 empty lines and go into inser mode
utils.nmap("<leader>L", "O<ESC>O")
utils.nmap("<leader>l", "o<cr>")
-- add line below without entering insert mode!
utils.nmap("<leader><Up>", ':<c-u>put!=repeat([\'\'],v:count)<bar>\']+1<cr>')
utils.nmap("<leader><Down>", ':<c-u>put =repeat([\'\'],v:count)<bar>\'[-1<cr>')
-- removes whitespace
utils.nmap('<leader>rspace', ':%s/\\s\\+$//e')
-- insert space
utils.nmap('<leader>i', 'i<space><esc>')
-- delete word forward in insert mode
utils.nmap('<leader>i', 'i<space><esc>')
-- delete word with ctrl backspace
utils.imap('<C-BS>', '<C-W>')
-- replace multiple words simultaniously
utils.nmap('<leader>x', '*``cgn')
utils.nmap('<leader>X', '#``cgn')
-- cut and copy content to next header #
utils.nmap('cO', ':.,/^#/-1d<cr>')
utils.nmap('cY', ':.,/^#/-1y<cr>')
-- split line in two
utils.nmap('<leader>sp', 'i<cr><esc>')
utils.nmap('<leader>wi', ':setlocal textwidth=80<cr>')
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
utils.omap('am', ':call MarkdownCodeBlock(1)<cr>')
utils.xmap('am', ':call MarkdownCodeBlock(1)<cr>')
utils.omap('im', ':call MarkdownCodeBlock(0)<cr>')
utils.xmap('im', ':call MarkdownCodeBlock(0)<cr>')
-- Markdown Previev
utils.nmap('<leader>mp', ':MarkdownPreview<CR>')
-- Fix Markdown Errors
utils.nmap('<leader>fx', ':<C-u>CocCommand markdownlint.fixAll<CR>')
utils.nmap('<leader>fmt', ':Pretty<CR>')
--" Markdown paste image

-- EXTERNAL --
-- Execute line under cursor in shell
utils.nmap('<leader>ex', ':exec \'!\'.getline(\'.\')<CR>')
-- Set spellcheck on/off
utils.nmap('<Leader>son', ':setlocal spell spelllang=en_us<CR>')
utils.nmap('<Leader>sof', ':set nospell<CR>')
-- Accept first grammar correction
utils.nmap('<Leader>c', '1z=')
-- Upload selected to ix.io
utils.vmap('<Leader>pp', ':w !curl -F "f:1=<--- ix.io<CR>')
-- setup mapping to call :LazyGit
utils.nmap('<leader>gg', ':LazyGit<CR>')

-- NAVIGATION --
-- Nvim Tree settings
utils.nmap('<leader>df', ':NvimTreeToggle<CR>')
utils.nmap('<Leader>da', ':NvimTreeFindFile<CR>')
-- Save buffer
utils.nmap('<leader>w', ':w<CR>')
-- Move screen to contain current line at the top
--local pathToVimInit = ':source ' .. vim.fn.expand('~/.config/nvim/init.vim<CR>')
utils.nmap('<leader>sv', ':source /home/decoder/.config/nvim/init.lua<CR>')
--nmap('<leader>sv', pathToVimInit)
-- jj in insert mode instead of ESC
utils.imap('jj', '<Esc>')
utils.imap('jk', '<Esc>')
-- Zoom split windows
utils.nmap('Zz', '<c-w>_ | <c-w>|')
utils.nmap('Zo', '<c-w>=')

-- PROGRAMMING --
-- Use `[g` and `]g` to navigate diagnostics
-- Apply AutoFix to problem on the current line.
-- Map function and class text objects
-- NOTE: Requires 'textDocument.documentSymbol' support from the language server.
utils.xmap('if', '<Plug>(coc-funcobj-i)')
utils.omap('if', '<Plug>(coc-funcobj-i)')
utils.xmap('af', '<Plug>(coc-funcobj-a)')
utils.omap('af', '<Plug>(coc-funcobj-a)')
-- Use CTRL-S for selections ranges.
-- Requires 'textDocument/selectionRange' support of language server.
utils.nmap('<silent>', '<C-s> <Plug>(coc-range-select)')
utils.xmap('<silent>', '<C-s> <Plug>(coc-range-select)')
-- vsnip settings
-- Expand
utils.imap('<expr>', '<C-j>   vsnip#expandable()  ? \'<Plug>(vsnip-expand)\'         : \'<C-j>')
utils.smap('<expr>', '<C-j>   vsnip#expandable()  ? \'<Plug>(vsnip-expand)\'         : \'<C-j>')

-- Expand or jump
utils.imap('<expr>', '<C-l>   vsnip#available(1)  ? \'<Plug>(vsnip-expand-or-jump)\' : \'<C-l>')
utils.smap('<expr>', '<C-l>   vsnip#available(1)  ? \'<Plug>(vsnip-expand-or-jump)\' : \'<C-l>')
-- Select or cut text to use as $TM_SELECTED_TEXT in the next snippet.
-- See https://github.com/hrsh7th/vim-vsnip/pull/50
utils.nmap('<leader>t', '<Plug>(vsnip-select-text)')
utils.xmap('<leader>t', '<Plug>(vsnip-select-text)')
utils.nmap('<leader>tc', '<Plug>(vsnip-cut-text)')
utils.xmap('<leader>tc', '<Plug>(vsnip-cut-text)')

-- Abbreviations
vim.cmd('abb cros Crossplane')
-- Telekasten
utils.nmap('<leader>tk', ':lua require(\'telekasten\').panel()<CR>')

-- Ranger
utils.tmap("<M-i>", "<C-\\><C-n>:RnvimrResize<CR>")
utils.nmap("<M-o>", ":RnvimrToggle<CR>")
utils.tmap("<M-o>", "<C-\\><C-n>:RnvimrToggle<CR>")

-- Harpoon
utils.nmap("<leader>ha", ":lua require(\"harpoon.mark\").add_file()<CR>")
utils.nmap("<leader>hm", ":lua require(\"harpoon.ui\").toggle_quick_menu()<CR>")
utils.nmap("<leader>hh", ":lua require(\"harpoon.ui\").nav_next()<CR>")
utils.nmap("<leader>hl", ":lua require(\"harpoon.ui\").nav_prev()<CR>")

-- Mdeval
vim.api.nvim_set_keymap('n', '<leader>ev', "<cmd>lua require 'mdeval'.eval_code_block()<CR>", { silent = true, noremap = true })

-- Startify
utils.lnmap("st", ":Startify<CR>") -- start Startify screen
