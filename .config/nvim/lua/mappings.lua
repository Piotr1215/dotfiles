local utils = require "utils"
local opts = { noremap = true, silent = true }

vim.keymap.set({ "n", "v" }, "<Space>", "<Nop>", { silent = true })
vim.g.mapleader = " "
vim.g.maplocalleader = " "
utils.nmap(";;", ":", { silent = false })
utils.vmap(";;", ":", { silent = false })

-- SAVE & CLOSE --
utils.lnmap("wa", ":wqa<cr>") -- save and close all
utils.lnmap("wq", ":wq<cr>") -- save and close all
utils.imap("jk", "<Esc>") -- esc and save
utils.nmap("<leader>w", ":wall<CR>") -- save all
utils.lnmap("qq", "@q") -- close all
utils.lnmap("qa", ":qa!<cr>") -- close all without saving
utils.lnmap("qf", ":q!<cr>") -- close current bufferall without saving
vim.keymap.set("n", "<leader>tf", ":!touch %<cr>", { silent = true, noremap = true }) -- touch file to reload observers
-- UNMAP --
utils.nmap("<nop>", "<Plug>NERDCommenterAltDelims") -- tab is for moving around only
vim.api.nvim_set_keymap("t", "<A-h>", [[<C-\><C-N><C-w>h]], { noremap = true })
vim.api.nvim_set_keymap("t", "<A-j>", [[<C-\><C-N><C-w>j]], { noremap = true })
vim.api.nvim_set_keymap("t", "<A-k>", [[<C-\><C-N><C-w>k]], { noremap = true })
vim.api.nvim_set_keymap("t", "<A-l>", [[<C-\><C-N><C-w>l]], { noremap = true })
vim.api.nvim_set_keymap("i", "<A-h>", [[<C-\><C-N><C-w>h]], { noremap = true })
vim.api.nvim_set_keymap("i", "<A-j>", [[<C-\><C-N><C-w>j]], { noremap = true })
vim.api.nvim_set_keymap("i", "<A-k>", [[<C-\><C-N><C-w>k]], { noremap = true })
vim.api.nvim_set_keymap("i", "<A-l>", [[<C-\><C-N><C-w>l]], { noremap = true })
vim.api.nvim_set_keymap("n", "<A-h>", [[<C-w>h]], { noremap = true })
vim.api.nvim_set_keymap("n", "<A-j>", [[<C-w>j]], { noremap = true })
vim.api.nvim_set_keymap("n", "<A-k>", [[<C-w>k]], { noremap = true })
vim.api.nvim_set_keymap("n", "<A-l>", [[<C-w>l]], { noremap = true })
vim.api.nvim_set_keymap("n", "<leader>tv", ":vsp term://", { noremap = true, silent = false })
vim.api.nvim_set_keymap("n", "<leader>th", ":sp term://", { noremap = true, silent = false })

-- Ensure 'notify' is required
local notify = require "notify"

-- Map the key to call an inline function for kubectl apply
vim.api.nvim_set_keymap("n", "<leader>ka", "", {
  noremap = true,
  silent = false,
  callback = function()
    local current_file = vim.fn.expand "%:p"
    local cmd = "kubectl apply -f " .. current_file
    local handle = io.popen(cmd)
    local result = handle:read "*a"
    handle:close()

    -- Use notify to print the result
    notify(result, "info")
  end,
})

-- Map the key to call an inline function for kubectl delete
vim.api.nvim_set_keymap("n", "<leader>kd", "", {
  noremap = true,
  silent = false,
  callback = function()
    local current_file = vim.fn.expand "%:p"
    local cmd = "kubectl delete -f " .. current_file
    local handle = io.popen(cmd)
    local result = handle:read "*a"
    handle:close()

    -- Use notify to print the result
    notify(result, "info")
  end,
})

-- NAVIGATION --
utils.nmap("<c-l>", "<c-w>l") -- move to right window
utils.nmap("<c-h>", "<c-w>h") -- move to left window
utils.nmap("<c-u>", "<c-u>zz") -- center screen after page up
utils.nmap("<c-d>", "<c-d>zz") -- center screen after page down
vim.keymap.set({ "n", "v" }, "<C-j>", [[10j<cr>]], opts) -- moves over virtual (wrapped) lines down
vim.keymap.set({ "n", "v" }, "<C-k>", [[10k<cr>]], opts) -- moves over virtual (wrapped) lines up
vim.api.nvim_set_keymap("n", "k", "v:count == 0 ? 'gk' : 'k'", { noremap = true, expr = true, silent = true }) -- moves up over virtual (wrapped) lines
vim.api.nvim_set_keymap("n", "j", "v:count == 0 ? 'gj' : 'j'", { noremap = true, expr = true, silent = true }) -- moves down over virtual (wrapped) lines
vim.api.nvim_set_keymap("n", "<Mgo-Right>", "gT", { noremap = true, silent = true }) -- move to next tab
utils.nmap("<BS>", "^") -- move to first non-bkgtgtgtgtlank character of the line
utils.vmap("<S-PageDown>", ":m '>+1<CR>gv=gv") -- Move Line Down in Visual Mode
utils.vmap("<S-PageUp>", ":m '<-2<CR>gv=gv") -- Move Line Up in Visual Mode
utils.nmap("<leader>k", ":m .-2<CR>==") -- Move Line Up in Normal Mode
utils.nmap("<leader>j", ":m .+1<CR>==") -- Move Line Down in Normal Mode
utils.nmap("<Leader>em", ":/\\V\\c\\<\\>") -- find exact match
vim.keymap.set("n", "J", "mzJ`z") -- join lines without spaces
vim.keymap.set("n", "n", "nzzzv") -- keep cursor centered
vim.keymap.set("n", "N", "Nzzzv") -- keep cursor centered
-- SEARCH AND REPLACE
utils.lnmap("sa", "ggVG") -- select all
utils.lnmap("r", ":%s/\\v/g<left><left>", { silent = false }) -- replace
utils.lnmap("ss", ":s/", { silent = false }) -- search and replace
utils.lnmap("SS", ":%s/", { silent = false }) -- search and replace
utils.vmap("<leader><C-s>", ":s/\\%V") -- Search only in visual selection usingb%V atom
utils.vmap("<C-r>", '"hy:%s/\\v<C-r>h//g<left><left>', { silent = false }) -- change selection
utils.nmap(",<space>", ":nohlsearch<CR>") -- Stop search highlight
utils.nmap("<leader>x", "*``cgn") -- replace word under cursor simultaneously
utils.nmap("<leader>X", "#``cgn") -- replace word under cursor simultaneously
-- MACROS --
utils.xmap("<leader>Q", ":'<,'>:normal @q<CR>") -- run macro from q register on visual selection
utils.tmap("<ESC>", "<C-\\><C-n>") -- exit terminal mode
vim.keymap.set("n", "<leader>ml", "^I-<Space>[<Space>]<Space><Esc>^j", { remap = true, silent = false }) -- prepend markdown list item on line
utils.vmap("srt", ":!sort -n -k 2<cr>") -- sort by second column
-- MANIPULATE TEXT --
utils.nmap("gp", "`[v`]") -- select pasted text
utils.imap("<C-l>", "<C-o>a") -- skip over a letter
utils.imap("<C-n>", "<C-e><C-o>A;<ESC>") -- insert semicolon at the end of the line
utils.nmap("<leader>LL", "O<ESC>O") -- insert 2 empty lines and go into inser mode
utils.nmap("<leader>ll", "o<cr>") -- insert 2 empty lines and go into inser mode
utils.nmap("<leader>l", ":lua add_empty_lines(true)<CR>") -- add line below without entering insert mode
utils.nmap("<leader>L", ":lua add_empty_lines(false)<CR>") -- add line above without entering insert mode
utils.nmap("<leader>i", "i<space><esc>") -- insert space
utils.nmap("<leader>sq", ':normal viWS"<CR>') -- skip over a letter
-- REGISTRIES --
utils.imap("<C-p>", "<C-o>:Telescope registers<cr><C-w>") -- The below mapping helps select from a register in the place of insert point
utils.lnmap("yl", '"*yy') -- yank line to the clipboard buffer
utils.nmap("<leader>df", ":%d<cr>") -- delete file content to black hole register
utils.nmap("<leader>yf", ":%y<cr>") -- yank file under cusror to the clipboard buffer
utils.nmap("<leader>yw", '"+yiw') -- yank word under cusror to the clipboard buffer
utils.nmap("<leader>yW", '"+yiW') -- yank WORD under cusror to the clipboard buffer
utils.lnmap("pa", '"*p') -- paste from clipboard buffer after the cursor
utils.lnmap("p", '"*P') -- paste from clipboard buffer before the cursor
utils.nmap("<leader>0", '"0p') -- paste from 0 (latest yank)
utils.nmap("<leader>1", '"1p') -- paste from 1 (latest delete)
utils.nmap("<leader>2", '"*p') -- paste from 2 (clipboard)
utils.nmap("<Leader>p", ":pu<CR>") -- paste from clipboard buffer after the cursor
utils.lnmap("dl", '"_dd') -- delete line to black hole register
utils.lnmap("d_", '"_D') -- delete till end of line to black hole register
utils.xmap("<leader>d", '"_d') -- delete selection to black hole register
-- PATH OPERATIONS --
utils.lnmap("cpf", ':let @+ = expand("%:p")<cr>') -- Copy current file name and path
-- Related script: /home/decoder/dev/dotfiles/scripts/__trigger_ranger.sh:7
utils.lnmap("cpfl", [[:let @+ = expand("%:p") . ':' . line('.')<cr>]]) -- Copy current file name, path, and line number
utils.lnmap("cpn", ':let @+ = expand("%:t")<cr>') -- Copy current file name
utils.nmap("<C-f>", ":Pretty<CR>") -- format json with pretty
utils.imap("<c-d>", "<c-o>daw") -- delete word forward in insert mode
vim.keymap.set("i", "<C-H>", "<c-w>", { noremap = true }) -- delete word forward in insert mode
utils.nmap("<leader>sp", "i<cr><esc>") -- split line in two
-- EXTERNAL COMMANDS --
vim.keymap.set("c", "<C-w>", "\\w*", { noremap = true }) -- copy word under cursor
vim.keymap.set("c", "<C-s>", "\\S*", { noremap = true }) -- copy WORD under cursor
utils.nmap("<leader>ex", ":.w !bash -e <cr>") -- execute current line and output to command line
utils.nmap("<leader>eX", ":%w !bash -e <cr>") -- exexute all lines and output to command line
utils.nmap("<leader>el", ":.!bash -e <cr>", { silent = false }) -- execute current line and replace with result
utils.nmap("<leader>eL", ":% !bash % <cr>") -- execute all lines and replace with result
utils.lnmap("cx", ":!chmod +x %<cr>") -- make file executable
utils.lnmap("ef", "<cmd>lua _G.execute_file_and_show_output()<CR>", { silent = false }) -- execute file and show output
utils.vmap("<Leader>pb", "w !bash share<CR>") -- upload selected to ix.io
-- FORMATTING --
utils.nmap("<leader>fmt", ":Pretty<CR>") -- format json with pretty
-- SPELLING --
utils.nmap("<Leader>son", ":setlocal spell spelllang=en_us<CR>") -- set spell check on
utils.nmap("<Leader>sof", ":set nospell<CR>") -- set spell check off
-- GIT RELATED --
vim.keymap.set({ "n", "v" }, "<leader>gb", ":GBrowse<cr>", opts) -- git browse current file in browser
vim.keymap.set("n", "<leader>gc", function()
  vim.cmd "GBrowse!"
end, opts) -- git browse current file and line in browser
vim.keymap.set("v", "<leader>gc", ":GBrowse!<CR>", { noremap = true, silent = false }) -- git browse current file and selected line in browser
utils.lnmap("gd", ":Gvdiffsplit<CR>") -- git diff current file
utils.lnmap("gu", ":Gdiffu<CR>") -- git diff current file
utils.nmap("<leader>gl", ":r !bash ~/dev/dotfiles/scripts/__generate_git_log.sh<CR>") -- generate git log
utils.lnmap("gh", ":Gclog %<CR>") -- show git log for current file
-- PROGRAMMING --
utils.imap("<expr>", "<C-l>   vsnip#available(1)  ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>") -- Vsnippet expand or jump
utils.smap("<expr>", "<C-l>   vsnip#available(1)  ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>") -- Vsnippet expand or jump
-- See https://github.com/hrsh7th/vim-vsnip/pull/50
utils.nmap("<leader>t", "<Plug>(vsnip-select-text)") -- Select or cut text to use as $TM_SELECTED_TEXT in the next snippet
utils.xmap("<leader>t", "<Plug>(vsnip-select-text)") -- Select or cut text to use as $TM_SELECTED_TEXT in the next snippet
utils.nmap("<leader>tc", "<Plug>(vsnip-cut-text)") -- Select or cut text to use as $TM_SELECTED_TEXT in the next snippet
utils.xmap("<leader>tc", "<Plug>(vsnip-cut-text)") -- Select or cut text to use as $TM_SELECTED_TEXT in the next snippet
-- ABBREVIATIONS --
vim.cmd "abb cros Crossplane"
vim.cmd "abb tcom TODO:(piotr1215)"

-- PLUGIN MAPPINGS --
-- Mdeval
vim.api.nvim_set_keymap(
  "n",
  "<leader>ev",
  "<cmd>lua require 'mdeval'.eval_code_block()<CR>",
  { silent = true, noremap = true }
)

-- Startify
utils.lnmap("st", ":Startify<CR>") -- start Startify screen
utils.lnmap("cd", ":cd %:p:h<CR>:pwd<CR>") -- change to current directory of active file and print out

-- Telescope
vim.keymap.set("n", "<Leader>ts", "<cmd>Telescope<cr>", opts)

-- Tmuxinator
-- utils.lnmap("wl", ":.!echo -n \"      layout:\" $(tmux list-windows | sed -n 's/.*layout \\(.*\\)] @.*/\\1/p')<CR>")

-- Transparent Plugin
utils.lnmap("tr", ":TransparentToggle<CR>")

-- FeMaco
utils.lnmap("ec", ":FeMaco<CR>")

-- Fzf Files
utils.lnmap("fl", ":Files<CR>")
utils.lnmap("lg", ":FzfLua live_grep<CR>")

-- Floaterm
utils.lnmap("tt", ":FloatermToggle<CR>")
utils.tmap("<leader>tt", "<C-\\><C-n>:FloatermToggle<CR>")

-- Trouble
vim.keymap.set("n", "<leader>xx", "<cmd>TroubleToggle<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>xw", "<cmd>TroubleToggle workspace_diagnostics<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>xd", "<cmd>TroubleToggle document_diagnostics<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>xl", "<cmd>TroubleToggle loclist<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>xq", "<cmd>TroubleToggle quickfix<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "gR", "<cmd>TroubleToggle lsp_references<cr>", { silent = true, noremap = true })

-- Scrollfix
utils.lnmap("f2", "<cmd>FIX 25<cr>")
utils.lnmap("f0", "<cmd>FIX -1<cr>")

-- Obsidian
utils.vmap("ol", ":ObsidianLink<leader>", { silent = false })
utils.lnmap("oq", ":ObsidianQuickSwitch<cr>")
utils.lnmap("on", ":ObsidianNew ", { silent = false })
utils.vmap("on", ":ObsidianLinkNew ", { silent = false })
utils.lnmap("os", ":ObsidianSearch<cr>")
utils.lnmap("ob", ":ObsidianBacklinks<cr>")
utils.lnmap("ot", ":ObsidianTags<cr>")

-- Copilot
vim.cmd [[
        imap <silent><script><expr> <C-s> copilot#Accept("\<CR>")
        let g:copilot_no_tab_map = v:true
]]
-- GoTo Preview
vim.keymap.set("n", "gtp", "<cmd>lua require('goto-preview').goto_preview_definition()<CR>", { noremap = true })

-- Yank Matching Lines
vim.api.nvim_set_keymap("n", "<Leader>ya", ":YankMatchingLines<CR>", { noremap = true, silent = true })

-- GpChat
local function keymapOptions(desc)
  return {
    noremap = true,
    silent = true,
    nowait = true,
    desc = "GPT prompt " .. desc,
  }
end

-- Restart nvim
vim.keymap.set("n", "<leader>-", function()
  vim.fn.system "bash __restart_nvim.sh"
end, { noremap = true, silent = true })

vim.keymap.set({ "n", "i" }, "<C-g>r", "<cmd>GpRewrite<cr>", keymapOptions "Inline Rewrite")
vim.keymap.set({ "n", "i" }, "<C-g>a", "<cmd>GpAppend<cr>", keymapOptions "Append")
vim.keymap.set({ "n", "i" }, "<C-g>b", "<cmd>GpPrepend<cr>", keymapOptions "Prepend")
vim.keymap.set({ "n", "i" }, "<C-g>e", "<cmd>GpEnew<cr>", keymapOptions "Enew")
vim.keymap.set({ "n", "i" }, "<C-g>p", "<cmd>GpPopup<cr>", keymapOptions "Popup")
vim.keymap.set("v", "<C-g>r", ":<C-u>'<,'>GpRewrite<cr>", keymapOptions "Visual Rewrite")
vim.keymap.set("v", "<C-g>a", ":<C-u>'<,'>GpAppend<cr>", keymapOptions "Visual Append")
vim.keymap.set("v", "<C-g>b", ":<C-u>'<,'>GpPrepend<cr>", keymapOptions "Visual Prepend")
vim.keymap.set("v", "<C-g>e", ":<C-u>'<,'>GpEnew<cr>", keymapOptions "Visual Enew")
vim.keymap.set("v", "<C-g>p", ":<C-u>'<,'>GpPopup<cr>", keymapOptions "Visual Popup")
vim.keymap.set({ "n", "i", "v", "x" }, "<C-g>s", "<cmd>GpStop<cr>", keymapOptions "Stop")

-- Nvim no neck pain Mappings
utils.lnmap("ne", "<cmd>NoNeckPain<cr>")

-- Nvim Telescope Crossplane Mappings
vim.keymap.set("n", "<Leader>tcm", ":Telescope telescope-crossplane crossplane_managed<CR>")
vim.keymap.set("n", "<Leader>tcr", ":Telescope telescope-crossplane crossplane_resources<CR>")

vim.keymap.set("n", "<Leader>mf", ":lua MiniFiles.open()<CR>", { noremap = true, silent = true })

-- Undotree
vim.keymap.set("n", "<leader>u", require("undotree").toggle, { noremap = true, silent = true })

-- Send to window
-- Visual mode mappings
utils.xmap("<leader><Left>", "<Plug>SendLeftV<cr>", keymapOptions "Visual Send Left")
utils.xmap("<leader><Down>", "<Plug>SendDownV<cr>", keymapOptions "Visual Send Down")
utils.xmap("<leader><Up>", "<Plug>SendUpV<cr>", keymapOptions "Visual Send Up")
utils.xmap("<leader><Right>", "<Plug>SendRightV<cr>", keymapOptions "Visual Send Right")
utils.lnmap("<Left>", "<Plug>SendLeft", keymapOptions "Send Left")
utils.lnmap("<Down>", "<Plug>SendDown", keymapOptions "Send Down")
utils.lnmap("<Up>", "<Plug>SendUp", keymapOptions "Send Up")
utils.lnmap("<Right>", "<Plug>SendRight", keymapOptions "Send Right")

-- Inlay Hints (nvim nighlty required)
if vim.lsp.inlay_hint then
  vim.keymap.set(
    "n",
    "<leader>ih",
    "<cmd>lua vim.lsp.inlay_hint(0, nil)<CR>",
    { silent = true, noremap = true, desc = "Toggle inlay hints" }
  )
end

-- Various text objects plugin mappings
local keymap = vim.keymap.set

keymap({ "o", "x" }, "ii", "<cmd>lua require('various-textobjs').indentation('inner', 'inner')<CR>")
keymap({ "o", "x" }, "ai", "<cmd>lua require('various-textobjs').indentation('outer', 'inner')<CR>")
keymap({ "o", "x" }, "iI", "<cmd>lua require('various-textobjs').indentation('inner', 'inner')<CR>")
keymap({ "o", "x" }, "aI", "<cmd>lua require('various-textobjs').indentation('outer', 'outer')<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').restOfIndentation()<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').greedyOuterIndentation('inner')<CR>")
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').greedyOuterIndentation('outer')<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').subword('inner')<CR>")
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').subword('outer')<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').toNextClosingBracket()<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').toNextQuotationMark()<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').anyQuote('inner')<CR>")
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').anyQuote('outer')<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').anyBracket('inner')<CR>")
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').anyBracket('outer')<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').restOfParagraph()<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').entireBuffer()<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').nearEoL()<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').lastChange()<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').lineCharacterwise('inner')<CR>")
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').lineCharacterwise('outer')<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').column()<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').multiCommentedLines()<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').notebookCell('inner')<CR>")
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').notebookCell('outer')<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').value('inner')<CR>")
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').value('outer')<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').key('inner')<CR>")
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').key('outer')<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').url()<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').diagnostic()<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').closedFold('inner')<CR>")
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').closedFold('outer')<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').chainMember('inner')<CR>")
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').chainMember('outer')<CR>")

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').visibleInWindow()<CR>")
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').restOfWindow()<CR>")

--------------------------------------------------------------------------------------
-- put these into the ftplugins or autocmds for the filetypes you want to use them with

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').mdlink('inner')<CR>", { buffer = true })
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').mdlink('outer')<CR>", { buffer = true })

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').mdEmphasis('inner')<CR>", { buffer = true })
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').mdEmphasis('outer')<CR>", { buffer = true })

keymap(
  { "o", "x" },
  "YOUR_MAPPING",
  "<cmd>lua require('various-textobjs').mdFencedCodeBlock('inner')<CR>",
  { buffer = true }
)
keymap(
  { "o", "x" },
  "YOUR_MAPPING",
  "<cmd>lua require('various-textobjs').mdFencedCodeBlock('outer')<CR>",
  { buffer = true }
)

keymap(
  { "o", "x" },
  "YOUR_MAPPING",
  "<cmd>lua require('various-textobjs').pyTripleQuotes('inner')<CR>",
  { buffer = true }
)
keymap(
  { "o", "x" },
  "YOUR_MAPPING",
  "<cmd>lua require('various-textobjs').pyTripleQuotes('outer')<CR>",
  { buffer = true }
)

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').cssSelector('inner')<CR>", { buffer = true })
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').cssSelector('outer')<CR>", { buffer = true })

keymap(
  { "o", "x" },
  "YOUR_MAPPING",
  "<cmd>lua require('various-textobjs').htmlAttribute('inner')<CR>",
  { buffer = true }
)
keymap(
  { "o", "x" },
  "YOUR_MAPPING",
  "<cmd>lua require('various-textobjs').htmlAttribute('outer')<CR>",
  { buffer = true }
)

keymap(
  { "o", "x" },
  "YOUR_MAPPING",
  "<cmd>lua require('various-textobjs').doubleSquareBrackets('inner')<CR>",
  { buffer = true }
)
keymap(
  { "o", "x" },
  "YOUR_MAPPING",
  "<cmd>lua require('various-textobjs').doubleSquareBrackets('outer')<CR>",
  { buffer = true }
)

keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').shellPipe('inner')<CR>", { buffer = true })
keymap({ "o", "x" }, "YOUR_MAPPING", "<cmd>lua require('various-textobjs').shellPipe('outer')<CR>", { buffer = true })
--
-- Decide there to autofill mapping based on space location
vim.cmd [[
     function! s:check_back_space() abort
       let col = col('.') - 1
       return !col || getline('.')[col - 1]  =~# '\s'
     endfunction
     ]]
