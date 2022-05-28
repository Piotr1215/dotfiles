vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local function map(mode, shortcut, command)
  vim.api.nvim_set_keymap(mode, shortcut, command, { noremap = true, silent = true })
end

local function emap(shortcut, command)
  map('', shortcut, command)
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

-- USER COMMANDS --
-- Format with default CocAction
vim.api.nvim_create_user_command(
  'Format',
  "call CocAction('format')",
  {bang = true}
)

--Open Buildin terminal vertical mode
vim.api.nvim_create_user_command(
  'VT',
  "vsplit | terminal <args>",
  {bang = false, nargs = '*'}
)

--Open Buildin terminal
vim.api.nvim_create_user_command(
  'T',
  ":split | resize 15 | terminal",
  {bang = false, nargs = '*'}
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
nmap('<leader>wi', ':setlocal textwidth=80<cr>')

-- MARKDOWN --
-- Operations on Code Block
omap('<silent>am', '<cmd>call s:MarkdowCodeBlock(1)<cr>')
xmap('<silent>am', '<cmd>call s:MarkdowCodeBlock(1)<cr>')
omap('<silent>im', '<cmd>call s:MarkdowCodeBlock(0)<cr>')
xmap('<silent>im', '<cmd>call s:MarkdowCodeBlock(0)<cr>')
-- Markdown Previev
nmap('<leader>mp', ':MarkdownPreview<CR>')
-- Fix Markdown Errors
nmap('<leader>fx', ':<C-u>CocCommand markdownlint.fixAll<CR>')
--vim.api.nvim_exec(
--     [[
--     function! s:MarkdowCodeBlock(outside)
--         call search('```', 'cb')
--         if a:outside
--             normal! Vo
--         else
--             normal! j0Vo
--         endif
--         call search('```')
--         if ! a:outside
--             normal! k
--         endif
--     endfunction
--     ]], false)
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
nmap('Zz', '<c-w>_ \\| <c-w>\\|')
nmap('Zo', '<c-w>=')
-- Split navigation
nmap('<S-L>', '<C-W><C-L>')
nmap('<S-H>', '<C-W><C-H>')
nmap('<S-U>', '<C-W><C-K>')
nmap('<S-J>', '<C-W><C-J>')
-- Floatterm settings
nmap('<Leader>fl', ':FloatermNew<CR>')
nmap('<Leader>ft', ':FloatermToggle<CR>')
nmap('<Leader>fs', ':FloatermShow<CR>')
nmap('<Leader>fh', ':FloatermHide<CR>')
nmap('<Leader>fn', ':FloatermNext<CR>')
nmap('<Leader>fc', ':FloatermKill<CR>')
nmap('<Leader>f', '[fzf-p]')
xmap('<Leader>f', '[fzf-p]')
nmap('<silent> [fzf-p]p',     ':<C-u>CocCommand fzf-preview.FromResources project_mru git<CR>')
nmap('<silent> [fzf-p]pf',    ':<C-u>CocCommand fzf-preview.ProjectFiles<CR>')
nmap('<silent> [fzf-p]gs',    ':<C-u>CocCommand fzf-preview.GitStatus<CR>')
nmap('<silent> [fzf-p]ga',    ':<C-u>CocCommand fzf-preview.GitActions<CR>')
nmap('<silent> [fzf-p]b',     ':<C-u>CocCommand fzf-preview.Buffers<CR>')
nmap('<silent> [fzf-p]B',     ':<C-u>CocCommand fzf-preview.AllBuffers<CR>')
nmap('<silent> [fzf-p]po',     ':<C-u>CocCommand fzf-preview.FromResources buffer project_mru<CR>')
nmap('<silent> [fzf-p]<C-o>', ':<C-u>CocCommand fzf-preview.Jumps<CR>')
nmap('<silent> [fzf-p]g;',    ':<C-u>CocCommand fzf-preview.Changes<CR>')
nmap('<silent> [fzf-p]q',     ':<C-u>CocCommand fzf-preview.QuickFix<CR>')
nmap('<silent> [fzf-p]L',     ':<C-u>CocCommand fzf-preview.LocationList<CR>')

-- PROGRAMMING --
-- Use `[g` and `]g` to navigate diagnostics
-- Use `:CocDiagnostics` to get all diagnostics of current buffer in location list.
nmap ('<silent>', '[g <Plug>(coc-diagnostic-prev)')
nmap ('<silent>', ']g <Plug>(coc-diagnostic-next)')
-- GoTo code navigation.
nmap ('<silent>', 'gd <Plug>(coc-definition)')
nmap ('<silent>', 'gy <Plug>(coc-type-definition)')
nmap ('<silent>', 'gimp <Plug>(coc-implementation)')
nmap ('<silent>', 'gr <Plug>(coc-references)')
-- Symbol renaming.
nmap ('<leader>rn', '<Plug>(coc-rename)')
-- Formatting selected code.
xmap ('<leader>fo', '<Plug>(coc-format-selected)')
nmap ('<leader>fo', '<Plug>(coc-format-selected)')
-- Applying codeAction to the selected region.
-- Example: `<leader>aap` for current paragraph
xmap ('<leader>a', '<Plug>(coc-codeaction-selected)')
nmap ('<leader>a', '<Plug>(coc-codeaction-selected)')
-- Remap keys for applying codeAction to the current buffer.
nmap ('<leader>ac', '<Plug>(coc-codeaction)')
-- Apply AutoFix to problem on the current line.
nmap ('<leader>qf', '<Plug>(coc-fix-current)')
-- Map function and class text objects
-- NOTE: Requires 'textDocument.documentSymbol' support from the language server.
xmap ('if', '<Plug>(coc-funcobj-i)')
omap ('if', '<Plug>(coc-funcobj-i)')
xmap ('af', '<Plug>(coc-funcobj-a)')
omap ('af', '<Plug>(coc-funcobj-a)')
-- Use CTRL-S for selections ranges.
-- Requires 'textDocument/selectionRange' support of language server.
nmap ('<silent>', '<C-s> <Plug>(coc-range-select)')
xmap ('<silent>', '<C-s> <Plug>(coc-range-select)')
-- vsnip settings
-- Expand
imap ('<expr>', '<C-j>   vsnip#expandable()  ? \'<Plug>(vsnip-expand)\'         : \'<C-j>')
smap ('<expr>', '<C-j>   vsnip#expandable()  ? \'<Plug>(vsnip-expand)\'         : \'<C-j>')

-- Expand or jump
imap ('<expr>', '<C-l>   vsnip#available(1)  ? \'<Plug>(vsnip-expand-or-jump)\' : \'<C-l>')
smap ('<expr>', '<C-l>   vsnip#available(1)  ? \'<Plug>(vsnip-expand-or-jump)\' : \'<C-l>')
-- Select or cut text to use as $TM_SELECTED_TEXT in the next snippet.
-- See https://github.com/hrsh7th/vim-vsnip/pull/50
nmap ('<leader>t', '<Plug>(vsnip-select-text)')
xmap ('<leader>t', '<Plug>(vsnip-select-text)')
nmap ('<leader>tc', '<Plug>(vsnip-cut-text)')
xmap ('<leader>tc', '<Plug>(vsnip-cut-text)')
