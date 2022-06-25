-- Local Functions {{{
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local api = vim.api
local sysname = vim.loop.os_uname().sysname

local function map(mode, shortcut, command)
     vim.api.nvim_set_keymap(mode, shortcut, command, { noremap = true, silent = true })
end

local function emap(shortcut, command)
     map('', shortcut, command)
end

--Leader normal mapping
local function lnmap(shortcut, command)
     local leader = "<leader>"..shortcut
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

-- }}}

-- Autocommands {{{
local indentSettings = vim.api.nvim_create_augroup("IndentSettings", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
     pattern = { "c", "cpp" },
     command = "setlocal expandtab shiftwidth=2 softtabstop=2 cindent",
     group = indentSettings,
})

vim.api.nvim_create_autocmd("FileType", {
     pattern = { "yaml" },
     command = "setlocal ts=2 sts=2 sw=4 expandtab",
     group = indentSettings,
})

vim.api.nvim_create_autocmd("FileType", {
     pattern = { "markdown", "python" },
     command = "setlocal expandtab shiftwidth=4 softtabstop=4 autoindent",
     group = indentSettings,
})

vim.api.nvim_create_autocmd("FileType", {
     pattern = { "go" },
     command = "set foldmethod=manual",
})

vim.api.nvim_create_autocmd("FileType", {
     pattern = { "go" },
     command = "nmap <buffer><silent> <leader>fld :%g/ {/normal! zf%<CR>",
})

vim.api.nvim_create_autocmd("FileType", {
     pattern = { "markdown" },
     command = "nmap <buffer><silent> <leader>p :call mdip#MarkdownClipboardImage()<CR>",
})

api.nvim_exec(
     [[
    augroup fileTypes
     autocmd FileType lua setlocal foldmethod=marker
     autocmd FileType go setlocal foldmethod=expr
     autocmd BufRead,BufNewFile .envrc set filetype=sh
    augroup end
  ]]  , false
)

api.nvim_exec(
     [[
    augroup helpers
     autocmd!
     autocmd TermOpen term://* startinsert
    augroup end
  ]]  , false
)

api.nvim_exec(
     [[
    augroup plantuml
     autocmd BufWritePost *.puml silent! !java -DPLANTUML_LIMIT_SIZE=8192 -jar /usr/local/bin/plantuml.jar -tsvg <afile> -o ./rendered
    augroup end
  ]]  , false
)

api.nvim_exec(
     [[
    augroup autoformat_settings
     autocmd FileType c,cpp,proto,javascript setlocal equalprg=clang-format
     autocmd FileType python AutoFormatBuffer yapf
    augroup end
  ]]  , false
)

api.nvim_exec(
     [[
    augroup last_cursor_position
     autocmd!
     autocmd BufReadPost *
       \ if line("'\"") > 1 && line("'\"") <= line("$") && &ft !~# 'commit' | execute "normal! g`\"zvzz" | endif
    augroup end
  ]]  , false
)
-- Compile packages on add
vim.cmd
[[
    augroup Packer
     autocmd!
     autocmd BufWritePost plugins.lua source <afile> | PackerSync
    augroup end
  ]]

if sysname == 'Darwin' then
     api.nvim_exec(
          [[
         augroup plant_folder
          autocmd FileType plantuml let g:plantuml_previewer#plantuml_jar_path = get(
              \  matchlist(system('cat `which plantuml` | grep plantuml.jar'), '\v.*\s[''"]?(\S+plantuml\.jar).*'),
              \  1,
              \  0
              \)
         augroup end
       ]]  , false)
end
require('telescope').setup {
     --  defaults   = {},
     --  pickers    = {},
     extensions = {
          file_browser = {}
     }
}
-- }}}

-- Telescope {{{
require('telescope').load_extension('file_browser')
require('telescope').load_extension('repo')
require('telescope').load_extension('fzf')
require('telescope').load_extension('projects')
local key = vim.api.nvim_set_keymap
local set_up_telescope = function()
     local set_keymap = function(mode, bind, cmd)
          key(mode, bind, cmd, { noremap = true, silent = true })
     end
     set_keymap('n', '<leader><leader>', [[<cmd>lua require('telescope.builtin').buffers()<CR>]])
     --set_keymap('n', '<leader>tf', [[<cmd>lua require('telescope.builtin').find_files({find_command = {'rg', '--files', '--hidden', '-g', '!.git' }})<CR>]])
     set_keymap('n', '<leader>fp', [[<cmd>lua require('telescope.builtin').find_files()<CR>]])
     set_keymap('n', '<leader>fr', [[<cmd>lua require'telescope'.extensions.repo.list{search_dirs = {"~/dev"}}<CR>]])
     set_keymap('n', '<leader>fgr', [[<cmd>lua require('telescope.builtin').live_grep()<CR>]])
     set_keymap('n', '<leader>fg', [[<cmd>lua require('telescope.builtin').git_files()<CR>]])
     set_keymap('n', '<leader>fo', [[<cmd>lua require('telescope.builtin').oldfiles()<CR>]])
     set_keymap('n', '<leader>fi', ':Telescope file_browser<CR>')
     set_keymap('n', '<leader>fst', [[<cmd>lua require('telescope.builtin').grep_string()<CR>]])
     set_keymap('n', '<leader>fb', [[<cmd>lua require('telescope.builtin').current_buffer_fuzzy_find()<CR>]])
     set_keymap('n', '<leader>fh', [[<cmd>lua require('telescope.builtin').help_tags()<CR>]])
     set_keymap('n', '<leader>ft', [[<cmd>lua require('telescope.builtin').tagstack()<CR>]])
     set_keymap('n', '<leader>re', [[<cmd>lua require('telescope.builtin').registers()<CR>]])
     set_keymap('n', '<leader>fT', [[<cmd>lua require('telescope.builtin').tags{ only_current_buffer = true }<CR>]])
     -- set_keymap('n', '<leader>sf', [[<cmd>lua vim.lsp.buf.formatting()<CR>]])
end

set_up_telescope()
-- }}}

-- Telekasten {{{
lnmap("tkf", ":lua require('telekasten').find_notes()<CR>") -- Move Line Up in Normal Mode
-- }}}

-- User commands {{{
-- Format with default CocAction
vim.api.nvim_create_user_command(
     'Format',
     "call CocAction('format')",
     { bang = true }
)

--Open Buildin terminal vertical mode
vim.api.nvim_create_user_command(
     'VT',
     "vsplit | terminal <args>",
     { bang = false, nargs = '*' }
)

--Open Buildin terminal
vim.api.nvim_create_user_command(
     'T',
     ":split | resize 15 | terminal",
     { bang = false, nargs = '*' }
)

--Execute shell command in a read-only scratchpad buffer
vim.api.nvim_create_user_command(
     'R',
     "new | setlocal buftype=nofile bufhidden=hide noswapfile | r !<args>",
     { bang = false, nargs = '*', complete = 'shellcmd' }
)

--Get diff for current file
vim.api.nvim_create_user_command(
     'Gdiff',
     "execute  'w !git diff --no-index -- % -'",
     { bang = false }
)

--Get diff for current file
vim.api.nvim_create_user_command(
     'Pretty',
     "CocCommand prettier.formatFile",
     { bang = true }
)
nmap("<C-f>", ":Pretty<CR>")
-- }}}


-- Hydra {{{
local Hydra = require("hydra")

Hydra({
name = "Change / Resize Window",
mode = { "n" },
body = "<C-w>",
config = {
	-- color = "pink",
},
heads = {
-- move between windows
{ "<C-h>", "<C-w>h" },
{ "<C-j>", "<C-w>j" },
{ "<C-k>", "<C-w>k" },
{ "<C-l>", "<C-w>l" },

-- resizing window
{ "H", "<C-w>3<" },
{ "L", "<C-w>3>" },
{ "K", "<C-w>2+" },
{ "J", "<C-w>2-" },

-- equalize window sizes
{ "e", "<C-w>=" },

-- close active window
{ "Q", ":q<cr>" },
{ "<C-q>", ":q<cr>" },

-- exit this Hydra
{ "q", nil, { exit = true, nowait = true } },
{ ";", nil, { exit = true, nowait = true } },
{ "<Esc>", nil, { exit = true, nowait = true } },
},
})

-- }}}

-- Mappings {{{
-- Map only if Linux
vim.api.nvim_set_keymap('n', 'k', "v:count == 0 ? 'gk' : 'k'", { noremap = true, expr = true, silent = true })
vim.api.nvim_set_keymap('n', 'j', "v:count == 0 ? 'gj' : 'j'", { noremap = true, expr = true, silent = true })
vim.keymap.set("n", "<C-j>", [[:keepjumps normal! j}k<cr>]], {noremap = true, silent = true})
vim.keymap.set("n", "<C-k>", [[:keepjumps normal! k{j<cr>]], {noremap = true, silent = true})
if sysname == 'Linux' then
     nmap('ö', '/')
     imap('ö', '/')
end
-- MOVE AROUND --
vmap("<S-PageDown>", ":m '>+1<CR>gv=gv") -- Move Line Down in Visual Mode
vmap("<S-PageUp>", ":m '<-2<CR>gv=gv") -- Move Line Up in Visual Mode
nmap("<leader>k", ":m .-2<CR>==") -- Move Line Up in Normal Mode
nmap("<leader>j", ":m .+1<CR>==") -- Move Line Down in Normal Mode
nmap("<Leader>nh", ":.,/^#/<CR>") -- Got to next markdown header

-- SEARCH & REPLACE --
-- Easy Motion Mappings
emap("<Leader>o", "<Plug>(easymotion-prefix)")
emap("<Leader>of", "<Plug>(easymotion-bd-f)")
emap("<Leader>ol", "<Plug>(easymotion-bd-w)")
emap("<Leader>oc", "<Plug>(easymotion-overwin-f2)")
-- Stop search highlight
nmap(",<space>", ":nohlsearch<CR>")
vmap("<C-r>", '"hy:%s/<C-r>h//gc<left><left><left>')
vmap("//", 'y/\\V<C-R>=escape(@",\'/\')<CR><CR>')

-- MACROS --
nmap("<Leader>q", "@q")
xmap("Q", ":'<,'>:normal @q<CR>")
lnmap("jq", ":g/{/.!jq .<CR>")

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
imap('<C-e>', '<C-o>dw<Left>')
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
-- Execute Command in scratchpad buffer
nmap('<leader>sr', '<Plug>SendRight<cr>')
xmap('<silent>srv', '<Plug>SendRightV<cr>')
nmap('<leader>sd', '<Plug>SendDown<cr>')
xmap('<silent>sdv', '<Plug>SendDownV<cr>')
-- setup mapping to call :LazyGit
nmap('<leader>gg', ':LazyGit<CR>')
-- NAVIGATION --
-- Nvim Tree settings
nmap('<leader>dd', ':NvimTreeToggle<CR>')
nmap('<Leader>da', ':NvimTreeFindFile<CR>')
-- Save buffer
nmap('<leader>w', ':w<CR>')
-- Move screen to contain current line at the top
--local pathToVimInit = ':source ' .. vim.fn.expand('~/.config/nvim/init.vim<CR>')
nmap('<leader>sv', ':source /home/decoder/.config/nvim/init.vim<CR>')
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

-- Telekasten
nmap ('<leader>tk', ':lua require(\'telekasten\').panel()<CR>')
-- }}}
