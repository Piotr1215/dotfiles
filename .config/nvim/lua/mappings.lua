vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.g.mapleader = " "
vim.g.maplocalleader = " "

function map(mode, shortcut, command)
  vim.api.nvim_set_keymap(mode, shortcut, command, { nmap = true, silent = true })
end

function emap(shortcut, command)
  map('', shortcut, command)
end

function nmap(shortcut, command)
  map('n', shortcut, command)
end

function imap(shortcut, command)
  map('i', shortcut, command)
end

function vmap(shortcut, command)
  map('v', shortcut, command)
end

function cmap(shortcut, command)
  map('c', shortcut, command)
end

function tmap(shortcut, command)
  map('t', shortcut, command)
end

function xmap(shortcut, command)
  map('x', shortcut, command)
end

-- USER COMMANDS --
-- Format with default CocAction
vim.api.nvim_create_user_command(
  'Format',
  "call CocAction('format')",
  {bang = true}
)

--Execute shell command in a read-only scratchpad buffer
vim.api.nvim_create_user_command(
  'R',
  "new | setlocal buftype=nofile bufhidden=hide noswapfile | r !<args>",
  {bang = false, nargs = '*', complete = 'shellcmd'}
)

--Get diff for current file
vim.api.nvim_create_user_command(
  'Gdiff',
  "execute  'w !git diff --no-index -- % -'",
  {bang = false}
)

--Get diff for current file
vim.api.nvim_create_user_command(
  'Pretty',
  "CocCommand prettier.formatFile",
  {bang = true}
)
nmap("<C-f>", ":Pretty<CR>")

-- MOVE AROUND --
vmap("<S-PageDown>", ":m '>+1<CR>gv=gv")     -- Move Line Down in Visual Mode
vmap("<S-PageUp>", ":m '<-2<CR>gv=gv")       -- Move Line Up in Visual Mode
nmap("<leader>k", ":m .-2<CR>==")            -- Move Line Up in Normal Mode
nmap("<leader>j", ":m .+1<CR>==")            -- Move Line Down in Normal Mode

nmap("<Leader>nh", ":.,/^#/<CR>")            -- Got to next markdown header

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

-- MANIPULATE TEXT --
-- Insert 2 empty lines and go into inser mode
nmap("<leader>L", "O<ESC>O")
nmap("<leader>l", "o<cr>")
-- Select last pasted text
nmap("gp", "`[v`]")
-- Add line below without entering insert mode!
nmap("<leader><Up>",   ':<c-u>put!=repeat([\'\'],v:count)<bar>\']+1<cr>')
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

-- EXTERNAL --
-- Execute line under cursor in shell
nmap('<leader>ex', ':exec \'!\'.getline(\'.\')<CR>')
-- Set spellcheck on/off
nmap('<Leader>son', ':setlocal spell spelllang=en_us<CR>')
nmap('<Leader>sof', ':set nospell<CR>')
-- Accept first grammar correction
nmap('<Leader>c', '1z=')
-- Upload selected to ix.io
vmap ('<Leader>pp', ':w !curl -F "f:1=<--- ix.io<CR>')
-- Execute Command in scratchpad buffer
nmap('<leader>sr', '<Plug>SendRight<cr>')
xmap('<silent>srv', '<Plug>SendRightV<cr>')
nmap('<leader>sd', '<Plug>SendDown<cr>')
xmap('<silent>sdv', '<Plug>SendDownV<cr>')
-- setup mapping to call :LazyGit
nmap('<leader>gg', ':LazyGit<CR>')

-- NAVIGATION --
-- Netrw settings
nmap('<leader>dd', ':Lexplore %:p:h<CR>')
nmap('<Leader>da', ':Lexplore<CR>')
-- Save buffer
nmap('<leader>w', ':w<CR>')
-- Move screen to contain current line at the top
nmap('<leader>sv', ':source ${HOME}/.config/nvim/init.vim<CR>')
-- jj in insert mode instead of ESC
imap('jj', '<Esc>')
imap('jk', '<Esc>')
-- Zoom split windows
--nmap('Zz', '<c-w>_ \| <c-w>\|')
--nmap('Zo', '<c-w>=')
-- Split navigation
nmap('<S-L>', '<C-W><C-L>')
nmap('<S-H>', '<C-W><C-H>')
nmap('<S-U>', '<C-W><C-K>')
nmap('<S-J>', '<C-W><C-J>')

