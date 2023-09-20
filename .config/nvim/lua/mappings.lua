local utils = require('utils')
local opts = { noremap = true, silent = true }

vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- MOVE AROUND --
utils.lnmap("wa", ":wqa<cr>")
utils.lnmap("qa", ":qa!<cr>")
utils.lnmap(";q", ":qa<cr>")
utils.lnmap(";w", ":wqa<cr>")
utils.lnmap(";e", ":!bash % ", { silent = false })
utils.nmap("<nop>", "<Plug>Markdown_Fold")               -- tab is for moving around only
utils.lnmap("nh", "<Plug>Markdown_MoveToNextHeader")     -- tab is for moving around only
utils.lnmap("ph", "<Plug>Markdown_MoveToPreviousHeader") -- tab is for moving around only
-- center screen after moving pageup or down
utils.nmap("<c-d>", "<c-d>zz")
utils.nmap("<c-u>", "<c-u>zz")
utils.nmap(";;", ":", { silent = false })
utils.vmap(";;", ":", { silent = false })
-- enter search and replace
utils.lnmap("sa", "ggVG")
utils.lnmap("r", ":%s/\\v/g<left><left>", { silent = false })
-- j/k moves over virtual (wrapped) lines
vim.api.nvim_set_keymap('n', 'k', "v:count == 0 ? 'gk' : 'k'", { noremap = true, expr = true, silent = true })
vim.api.nvim_set_keymap('n', 'j', "v:count == 0 ? 'gj' : 'j'", { noremap = true, expr = true, silent = true })
-- Navigate between paragraphs and add to jumplist
vim.keymap.set("n", "<C-j>", [[:keepjumps normal! j}k<cr>]], opts)
vim.keymap.set("n", "<C-k>", [[:keepjumps normal! k{j<cr>]], opts)
vim.api.nvim_set_keymap('n', '<S-PageUp>', 'gT', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<S-PageDown>', 'gt', { noremap = true, silent = true })
utils.nmap("<BS>", "^")
utils.vmap("<S-PageDown>", ":m '>+1<CR>gv=gv") -- Move Line Down in Visual Mode
utils.vmap("<S-PageUp>", ":m '<-2<CR>gv=gv")   -- Move Line Up in Visual Mode
utils.nmap("<leader>k", ":m .-2<CR>==")        -- Move Line Up in Normal Mode
utils.nmap("<leader>j", ":m .+1<CR>==")        -- Move Line Down in Normal Mode

-- CHAT GPT KEYMAPS --
utils.lnmap("ct", ":ChatGPT<cr>")
utils.lnmap("ca", ":ChatGPTActAs<cr>")
utils.lnmap("co", ":ChatGPTCompleteCode<cr>")
utils.lnmap("ce", ":ChatGPTEditWithInstructions<cr>")
utils.vmap("<leader>cr", ":ChatGPTRun ", { silent = false })
utils.lnmap("cr", ":ChatGPTRun ", { silent = false })

-- SEARCH & REPLACE --
utils.nmap("<Leader>em", ":/\\V\\c\\<\\>") -- find exact match
vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- Nvim Leap Mappings
utils.emap("<Leader>ow", "<Plug>(leap-cross-window)")
-- Stop search highlight
utils.nmap(",<space>", ":nohlsearch<CR>")
utils.vmap("<C-r>", '"hy:%s/<C-r>h//gc<left><left><left>') -- Change selection
utils.vmap("//", 'y/\\V<C-R>=escape(@",\'/\')<CR><CR>')    -- Highlight selection
utils.vmap("<leader><C-s>", ":s/\\%V")                     -- Search only in visual selection usingb%V atom
utils.vmap("srt", ":!sort -n -k 2<cr>")

-- MACROS --
utils.nmap("<Leader>m", "@q")
utils.xmap("<leader>Q", ":'<,'>:normal @q<CR>")
utils.tmap("<ESC>", "<C-\\><C-n>")

-- MANIPULATE TEXT --
-- jump to next "" text
vim.api.nvim_set_keymap('n', 'cinq', '/"[^"]*"<CR>:nohlsearch<CR>ci"', { noremap = true, silent = true })

-- YAML fold
utils.lnmap('yi', ':set foldmethod=indent<CR>')
-- Registries
-- The below mapping helps select from a register in the place of insert point
utils.imap('<C-p>', '<C-o>:Telescope registers<cr><C-w>')
-- Yank
utils.lnmap('yl', '\"*yy')          -- yank line to the clipboard buffer
utils.nmap('<leader>df', ':%d<cr>') -- delete file content to black hole register
utils.nmap('<leader>yf', ':%y<cr>') -- yank file under cusror to the clipboard buffer
utils.nmap('<leader>yw', '"+yiw')   -- yank word under cusror to the clipboard buffer
utils.nmap('<leader>yW', '"+yiW')   -- yank WORD under cusror to the clipboard buffer
-- Paste
utils.lnmap('pa', '\"*p')           -- paste from clipboard buffer after the cursor
utils.lnmap('p', '\"*P')            -- paste from clipboard buffer before the cursor
utils.nmap("<leader>1", '"0p')      -- paste from 0 (latest yank)
utils.nmap("<leader>2", '"*p')      -- paste from 0 (latest yank)
-- Substitute
utils.nmap("<leader>sw", "\"_diwP") -- substitute current word with last yanked text
utils.nmap("<leader>sW", "\"_diWP") -- substitute current WORD with last yanked text
-- Delete
utils.lnmap('dl', '\"_dd')          -- delete line to black hole register
utils.lnmap('d_', '\"_D')           -- delete till end of line to black hole register
utils.xmap('<leader>d', '\"_d')     -- delete selection to black hole register

-- select pasted text
utils.nmap("gp", "`[v`]")
-- useful for passing over braces and quotations
utils.imap("<C-l>", "<C-o>a")
utils.imap("<C-n>", "<C-e><C-o>A;<ESC>")
-- set mark on this line ma
utils.imap(";[", "<c-o>ma")
utils.imap("']", "<c-o>mA")
-- Copy current file name
utils.lnmap("cpf", ":let @+ = expand(\"%:p\")<cr>")
-- insert 2 empty lines and go into inser mode
utils.nmap("<leader>O", "O<ESC>O")
utils.nmap("<leader>o", "o<cr>")

-- Format with pretty
utils.nmap("<C-f>", ":Pretty<CR>")
-- add line below without entering insert mode!
utils.nmap("<leader>L", ':<c-u>put!=repeat([\'\'],v:count)<bar>\']+1<cr>')
utils.nmap("<leader>l", ':<c-u>put =repeat([\'\'],v:count)<bar>\'[-1<cr>')
-- insert space
utils.nmap('<leader>i', 'i<space><esc>')
-- delete word forward in insert mode
utils.imap('<c-d>', '<c-o>daw')
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

utils.nmap('<leader>fmt', ':Pretty<CR>')
-- vim.keymap.set({ 'n' }, '<C-k>', function()       require('lsp_signature').toggle_float_win()
--end, { silent = true, noremap = true, desc = 'toggle signature' })
-- EXTERNAL --
-- Execute line under cursor in shell
utils.nmap('<leader>ex', ':.w !bash -e <cr>')                   -- execute current line and output to command line
utils.nmap('<leader>eX', ':%w !bash -e <cr>')                   -- exexute all lines and output to command line
utils.nmap('<leader>el', ':.!bash -e <cr>', { silent = false }) -- execute current line and replace with result
utils.nmap('<leader>eL', ':% !bash % <cr>')                     -- execute all lines and replace with result
utils.lnmap('cx', ':!chmod +x %<cr>')
-- Set spellcheck on/off
utils.nmap('<Leader>son', ':setlocal spell spelllang=en_us<CR>')
utils.nmap('<Leader>sof', ':set nospell<CR>')
-- Accept first grammar correction
-- utils.nmap('<Leader>c', '1z=')
-- Upload selected to ix.io
utils.vmap('<Leader>pb', "w !bash share<CR>")
utils.nmap('<Leader>p', ":pu<CR>")
utils.nmap('<Leader>hs', ":History<CR>")

-- setup mapping to call :LazyGit
utils.lnmap('gd', ':Gvdiffsplit<CR>')
utils.nmap('<leader>gg', ':LazyGit<CR>')
utils.nmap('<leader>gl', ':r !bash ~/dev/dotfiles/scripts/__generate_git_log.sh<CR>')

-- NAVIGATION --
-- Save buffer
utils.nmap('<leader>w', ':wall<CR>')
-- jj in insert mode instead of ESC
utils.imap('jj', '<Esc>')
utils.imap('jk', '<Esc>')
-- Zoom split windows
utils.nmap('Zz', '<c-w>_ | <c-w>|')
utils.nmap('Zo', '<c-w>=')
-- quickfix window
utils.lnmap('qf', ':copen<CR>')
-- close tab
utils.lnmap('tcl', ':tabc<CR>')

-- PROGRAMMING --
-- Expand or jump
utils.imap('<expr>', '<C-l>   vsnip#available(1)  ? \'<Plug>(vsnip-expand-or-jump)\' : \'<C-l>')
utils.smap('<expr>', '<C-l>   vsnip#available(1)  ? \'<Plug>(vsnip-expand-or-jump)\' : \'<C-l>')
-- Select or cut text to use as $TM_SELECTED_TEXT in the next snippet
-- See https://github.com/hrsh7th/vim-vsnip/pull/50
utils.nmap('<leader>t', '<Plug>(vsnip-select-text)')
utils.xmap('<leader>t', '<Plug>(vsnip-select-text)')
utils.nmap('<leader>tc', '<Plug>(vsnip-cut-text)')
utils.xmap('<leader>tc', '<Plug>(vsnip-cut-text)')

-- Abbreviations
vim.cmd('abb cros Crossplane')

-- Harpoon
utils.nmap("<leader>ha", ":lua require(\"harpoon.mark\").add_file()<CR>")
utils.nmap("<leader>hm", ":lua require(\"harpoon.ui\").toggle_quick_menu()<CR>")
utils.nmap("<leader>hh", ":lua require(\"harpoon.ui\").nav_next()<CR>")
utils.nmap("<leader>hl", ":lua require(\"harpoon.ui\").nav_prev()<CR>")

-- Mdeval
vim.api.nvim_set_keymap('n', '<leader>ev', "<cmd>lua require 'mdeval'.eval_code_block()<CR>",
  { silent = true, noremap = true })

-- Startify
utils.lnmap("st", ":Startify<CR>")         -- start Startify screen
utils.lnmap("cd", ":cd %:p:h<CR>:pwd<CR>") -- change to current directory of active file and print out

-- Telescope
vim.keymap.set("n", "<Leader>ts", "<cmd>Telescope<cr>", opts)

-- Telekasten
utils.lnmap("tkf", ":lua require('telekasten').find_notes()<CR>")
utils.nmap('<leader>tk', ':lua require(\'telekasten\').panel()<CR>')

-- Tmuxinator
-- utils.lnmap("wl", ":.!echo -n \"      layout:\" $(tmux list-windows | sed -n 's/.*layout \\(.*\\)] @.*/\\1/p')<CR>")

-- Transparent Plugin
utils.lnmap("tr", ":TransparentToggle<CR>")

-- FeMaco
utils.lnmap("ec", ":FeMaco<CR>")

-- Fzf Files
utils.lnmap("fl", ":Files<CR>")

-- Floaterm
utils.lnmap("tt", ":FloatermToggle<CR>")
utils.tmap("<leader>tt", "<C-\\><C-n>:FloatermToggle<CR>")

-- -- Svart
-- vim.keymap.set({ "n", "x", "o" }, "s", "<Cmd>Svart<CR>")       -- begin search
-- vim.keymap.set({ "n", "x", "o" }, "S", "<Cmd>SvartRepeat<CR>") -- repeat with last searched query

-- Trouble
-- Lua
vim.keymap.set("n", "<leader>xx", "<cmd>TroubleToggle<cr>",
  { silent = true, noremap = true }
)
vim.keymap.set("n", "<leader>xw", "<cmd>TroubleToggle workspace_diagnostics<cr>",
  { silent = true, noremap = true }
)
vim.keymap.set("n", "<leader>xd", "<cmd>TroubleToggle document_diagnostics<cr>",
  { silent = true, noremap = true }
)
vim.keymap.set("n", "<leader>xl", "<cmd>TroubleToggle loclist<cr>",
  { silent = true, noremap = true }
)
vim.keymap.set("n", "<leader>xq", "<cmd>TroubleToggle quickfix<cr>",
  { silent = true, noremap = true }
)
vim.keymap.set("n", "gR", "<cmd>TroubleToggle lsp_references<cr>",
  { silent = true, noremap = true }
)

-- Crates
utils.lnmap("cu", "lua require('crates').upgrade_crate()")

-- NoNeckPain
utils.lnmap("ne", "<cmd>NoNeckPain<cr>")

-- Scrollfix
utils.lnmap("f2", "<cmd>FIX 25<cr>")
utils.lnmap("f0", "<cmd>FIX -1<cr>")

-- Obsidian
utils.vmap("ol", ":ObsidianLink<cr>")
utils.lnmap("oq", ":ObsidianQuickSwitch<cr>")
utils.lnmap("on", ":ObsidianNew ", { silent = false })
utils.lnmap("os", ":ObsidianSearch<cr>")
utils.lnmap("ob", ":ObsidianBacklinks<cr>")
-- vim.keymap.set("n", "gf", function()
-- if require("obsidian").util.cursor_on_markdown_link() then
-- return "<cmd>ObsidianFollowLink<CR>"
-- else
-- return "gf"
-- end
-- end, { noremap = false, expr = true })

-- Copilot
vim.cmd([[
        imap <silent><script><expr> <C-s> copilot#Accept("\<CR>")
        let g:copilot_no_tab_map = v:true
]])

-- GoTo Preview
vim.keymap.set("n", "gtp", "<cmd>lua require('goto-preview').goto_preview_definition()<CR>", { noremap = true })

-- My Plugins
-- Yank Matching Lines
vim.api.nvim_set_keymap('n', '<Leader>ya', ':YankMatchingLines<CR>', { noremap = true, silent = true })
