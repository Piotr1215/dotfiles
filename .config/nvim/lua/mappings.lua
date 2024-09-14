-- Utils and Basic Settings
local shell = require "user_functions.shell_integration"
local opts = { noremap = true, silent = true }

-- Leader Key Configuration
vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.keymap.set({ "n", "v" }, "<Space>", "<Nop>", opts)

-- Save & Close Mappings
vim.keymap.set("n", "<leader>wa", ":wqa<CR>", { desc = "Save and close all" })
vim.keymap.set("n", "<leader>wq", ":wq<CR>", { desc = "Save and close current buffer" })
vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })
vim.keymap.set("n", "<leader>w", ":wall<CR>", { desc = "Save all" })
vim.keymap.set("n", "<leader>qq", "@q", { desc = "Execute macro in 'q' register" })
vim.keymap.set("n", "<leader>qa", ":qa!<CR>", { desc = "Quit all without saving" })
vim.keymap.set("n", "<leader>qf", ":q!<CR>", { desc = "Quit current buffer without saving" })
vim.keymap.set("n", "<leader>tf", ":!touch %<CR>", { silent = true, desc = "Touch file to reload observers" })
vim.keymap.set("n", "<leader>Tsv", ":vsp term://<CR>", { silent = false, desc = "Vertical split terminal" })
vim.keymap.set("n", "<leader>Tsh", ":sp term://<CR>", { silent = false, desc = "Horizontal split terminal" })
vim.keymap.set("n", "L", "vg_", { desc = "Select to end of line" })

-- Window Resizing
vim.keymap.set("n", "<leader>_", "5<C-w>-", { remap = true, silent = false, desc = "Decrease window height" })
vim.keymap.set("n", "<leader>+", "5<C-w>+", { remap = true, silent = false, desc = "Increase window height" })

-- Navigation Mappings
local nvim_tmux_nav = require "nvim-tmux-navigation"
-- Normal Mode
vim.keymap.set("n", "<C-h>", nvim_tmux_nav.NvimTmuxNavigateLeft, opts)
vim.keymap.set("n", "<C-j>", nvim_tmux_nav.NvimTmuxNavigateDown, opts)
vim.keymap.set("n", "<C-k>", nvim_tmux_nav.NvimTmuxNavigateUp, opts)
vim.keymap.set("n", "<C-l>", nvim_tmux_nav.NvimTmuxNavigateRight, opts)
vim.keymap.set("n", "<A-m>", nvim_tmux_nav.NvimTmuxNavigateNext, opts)
-- Insert Mode
vim.keymap.set("i", "<C-h>", "<Esc><Cmd>lua require('nvim-tmux-navigation').NvimTmuxNavigateLeft()<CR>", opts)
vim.keymap.set("i", "<C-j>", "<Esc><Cmd>lua require('nvim-tmux-navigation').NvimTmuxNavigateDown()<CR>", opts)
vim.keymap.set("i", "<C-k>", "<Esc><Cmd>lua require('nvim-tmux-navigation').NvimTmuxNavigateUp()<CR>", opts)
vim.keymap.set("i", "<C-l>", "<Esc><Cmd>lua require('nvim-tmux-navigation').NvimTmuxNavigateRight()<CR>", opts)
vim.keymap.set("i", "<A-m>", "<Esc><Cmd>lua require('nvim-tmux-navigation').NvimTmuxNavigateNext()<CR>", opts)
-- Terminal Mode
vim.keymap.set("t", "<C-h>", "<C-\\><C-n><C-w>h", opts)
vim.keymap.set("t", "<C-j>", "<C-\\><C-n><C-w>j", opts)
vim.keymap.set("t", "<C-k>", "<C-\\><C-n><C-w>k", opts)
vim.keymap.set("t", "<C-l>", "<C-\\><C-n><C-w>l", opts)
vim.keymap.set("t", "<A-m>", "<C-\\><C-n><A-m>", opts)

-- Scrolling and Centering
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Page up and center" })
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Page down and center" })
vim.keymap.set({ "n", "v" }, "<A-j>", "10j", { desc = "Move down 10 lines" })
vim.keymap.set({ "n", "v" }, "<A-k>", "10k", { desc = "Move up 10 lines" })
vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true, desc = "Up over wrapped lines" })
vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true, desc = "Down over wrapped lines" })
vim.keymap.set("n", "<M-l>", "<cmd>tabnext<CR>", { desc = "Next tab" })
vim.keymap.set("n", "<M-h>", "<cmd>tabprevious<CR>", { desc = "Previous tab" })
vim.keymap.set("n", "<BS>", "^", { desc = "Move to first non-blank character" })

-- Moving Lines
vim.keymap.set("v", "<S-PageDown>", ":m '>+1<CR>gv=gv", { desc = "Move line down in visual mode" })
vim.keymap.set("v", "<S-PageUp>", ":m '<-2<CR>gv=gv", { desc = "Move line up in visual mode" })
vim.keymap.set("n", "<leader>mj", ":m .+1<CR>==", { desc = "Move line down in normal mode" })
vim.keymap.set("n", "<leader>mk", ":m .-2<CR>==", { desc = "Move line up in normal mode" })
vim.keymap.set("v", "<leader>mj", ":m '>+1<CR>gv=gv", { desc = "Move line down in visual mode" })
vim.keymap.set("v", "<leader>mk", ":m '<-2<CR>gv=gv", { desc = "Move line up in visual mode" })

-- Center Cursor After Search
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result and center" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous search result and center" })

-- Search and Replace
vim.keymap.set("n", "<leader>ss", ":s/\\v", { silent = false, desc = "Search and replace on line" })
vim.keymap.set("n", "<leader>SS", ":%s/\\v", { silent = false, desc = "Search and replace in file" })
vim.keymap.set("v", "<leader><C-s>", ":s/\\%V", { desc = "Search in visual selection" })
vim.keymap.set("v", "<C-r>", '"hy:%s/\\v<C-r>h//g<left><left>', { silent = false, desc = "Replace selection" })
vim.keymap.set("n", ",<space>", ":nohlsearch<CR>", { desc = "Stop search highlight" })
vim.keymap.set("n", "<leader>x", "*``cgn", { desc = "Replace word under cursor" })
vim.keymap.set("n", "<leader>X", "#``cgn", { desc = "Replace word under cursor (backwards)" })
vim.keymap.set("n", "<leader>em", ":/\\V\\c\\<\\>", { silent = false, desc = "Find exact match" })

-- Macros and Text Manipulation
vim.keymap.set("x", "<leader>Q", ":'<,'>:normal @q<CR>", { desc = "Run macro from 'q' register" })
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
vim.keymap.set(
  "n",
  "<leader>ml",
  "^I- [ ] <Esc>^j",
  { remap = true, silent = false, desc = "Prepend markdown list item" }
)
vim.keymap.set("v", "srt", ":!sort -n -k 2<CR>", { desc = "Sort by second column" })
vim.keymap.set("n", "J", "mzJ`z", { desc = "Join lines without moving cursor" })
vim.keymap.set("n", "<leader>gp", "`[v`]", { desc = "Select pasted text" })
vim.keymap.set("i", "<A-l>", "<C-o>a", { desc = "Skip over a letter" })
vim.keymap.set("i", "<C-n>", "<C-e><C-o>A;<Esc>", { desc = "Insert semicolon at end of line" })
vim.keymap.set("n", "<leader>is", "i <Esc>", { desc = "Insert space in normal mode" })
vim.keymap.set("n", "<leader>sq", ':normal viWS"<CR>', { desc = "Surround with quotation" })
vim.keymap.set("n", "<leader>sp", "i<CR><Esc>", { desc = "Split line" })

-- Insert Empty Lines
vim.keymap.set("n", "<leader>al", function()
  shell.add_empty_lines { below = true }
end, { remap = true, silent = false, desc = "Add empty line below" })
vim.keymap.set("n", "<leader>aL", function()
  shell.add_empty_lines { below = false }
end, { remap = true, silent = false, desc = "Add empty line above" })
vim.keymap.set("n", "<leader>il", function()
  shell.add_empty_lines { below = true, insert = true }
end, { remap = true, silent = false, desc = "Insert empty line below and enter insert mode" })
vim.keymap.set("n", "<leader>iL", function()
  shell.add_empty_lines { below = false, insert = true }
end, { remap = true, silent = false, desc = "Insert empty line above and enter insert mode" })

-- Clipboard and Registers
vim.keymap.set("i", "<C-p>", function()
  require("telescope.builtin").registers()
end, { silent = false, desc = "Paste register in insert mode" })
vim.keymap.set("n", "<leader>yl", '"+yy', { desc = "Yank line to clipboard" })
vim.keymap.set("n", "<leader>df", ":%d<CR>", { desc = "Delete file content" })
vim.keymap.set("n", "<leader>yf", ":%y<CR>", { desc = "Yank file content" })
vim.keymap.set("n", "<leader>yw", '"+yiw', { desc = "Yank word under cursor to clipboard" })
vim.keymap.set("n", "<leader>yW", '"+yiW', { desc = "Yank WORD under cursor to clipboard" })
vim.keymap.set("n", "<leader>p", '"+p', { desc = "Paste from clipboard after cursor" })
vim.keymap.set("n", "<leader>P", '"+P', { desc = "Paste from clipboard before cursor" })
vim.keymap.set("n", "<leader>0", '"0p', { desc = "Paste from yank register" })
vim.keymap.set("n", "<leader>1", '"1p', { desc = "Paste from delete register" })
vim.keymap.set("n", "<leader>2", '"*p', { desc = "Paste from system clipboard" })
vim.keymap.set("n", "<leader>dl", '"_dd', { desc = "Delete line without yanking" })
vim.keymap.set("n", "<leader>d_", '"_D', { desc = "Delete to end of line without yanking" })
vim.keymap.set("x", "<leader>d", '"_d', { desc = "Delete selection without yanking" })

-- Path Operations
vim.keymap.set("n", "<leader>cpf", function()
  local path = vim.fn.expand "%:p"
  vim.fn.setreg("+", path)
  print("Copied path to clipboard: " .. path)
end, { desc = "Copy file path" })
vim.keymap.set("n", "<leader>cpl", function()
  local path_line = vim.fn.expand "%:p" .. ":" .. vim.fn.line "."
  vim.fn.setreg("+", path_line)
  print("Copied file path and line number to clipboard: " .. path_line)
end, { desc = "Copy file path with line number" })
vim.keymap.set("n", "<leader>cpn", function()
  local filename = vim.fn.expand "%:t"
  vim.fn.setreg("+", filename)
  print("Copied filename to clipboard: " .. filename)
end, { desc = "Copy filename" })

-- External Commands
vim.keymap.set("c", "<C-w>", "\\w*", { noremap = true, desc = "Copy word under cursor" })
vim.keymap.set("c", "<C-s>", "\\S*", { noremap = true, desc = "Copy WORD under cursor" })
vim.keymap.set("n", "<leader>ex", ":.w !bash -e<CR>", { desc = "Execute current line" })
vim.keymap.set("n", "<leader>eX", ":%w !bash -e<CR>", { desc = "Execute entire file" })
vim.keymap.set("n", "<leader>el", ":.!bash -e<CR>", { silent = false, desc = "Execute line and replace" })
vim.keymap.set("n", "<leader>eL", ":%!bash %<CR>", { desc = "Execute file and replace" })
vim.keymap.set("n", "<leader>cx", ":!chmod +x %<CR>", { desc = "Make file executable" })
vim.keymap.set("n", "<leader>ef", function()
  require("user_functions.shell_integration").execute_file_and_show_output()
end, { silent = false, desc = "Execute file and show output" })
vim.keymap.set("v", "<leader>pb", "w !bash share<CR>", { desc = "Upload selection to ix.io" })

-- Spelling
vim.keymap.set("n", "<leader>son", ":setlocal spell spelllang=en_us<CR>", { desc = "Enable spell check" })
vim.keymap.set("n", "<leader>sof", ":set nospell<CR>", { desc = "Disable spell check" })

-- Git Mappings
vim.keymap.set({ "n", "v" }, "<leader>gbf", ":GBrowse<CR>", { desc = "Open file in browser" })
vim.keymap.set("n", "<leader>gbc", ":GBrowse!<CR>", { desc = "Copy file URL" })
vim.keymap.set("v", "<leader>gbl", ":GBrowse!<CR>", { silent = false, desc = "Copy selected lines URL" })
vim.keymap.set("n", "<leader>gd", ":Gvdiffsplit<CR>", { desc = "Git diff split" })
vim.keymap.set("n", "<leader>gu", ":Gdiffu<CR>", { desc = "Git diff update" })
vim.keymap.set(
  "n",
  "<leader>gl",
  ":r !bash ~/dev/dotfiles/scripts/__generate_git_log.sh<CR>",
  { desc = "Generate git log" }
)
vim.keymap.set("n", "<leader>gh", ":Gclog %<CR>", { desc = "Show git log for current file" })

-- Plugin Mappings
-- Mdeval
vim.keymap.set(
  "n",
  "<leader>ev",
  "<cmd>lua require('mdeval').eval_code_block()<CR>",
  { silent = true, desc = "Evaluate code block" }
)

-- Startify
vim.keymap.set("n", "<leader>st", ":Startify<CR>", { desc = "Open Startify" })
vim.keymap.set("n", "<leader>cd", ":cd %:p:h<CR>:pwd<CR>", { desc = "Change to file directory and print" })

-- Telescope
vim.keymap.set("n", "<leader>ts", "<cmd>Telescope<CR>", { desc = "Open Telescope" })

-- Transparent Plugin
vim.keymap.set("n", "<leader>tr", ":TransparentToggle<CR>", { desc = "Toggle transparency" })

-- FeMaco
vim.keymap.set("n", "<leader>ec", ":FeMaco<CR>", { desc = "Open FeMaco" })

-- Trouble
vim.keymap.set("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<CR>", { desc = "Toggle diagnostics" })
vim.keymap.set(
  "n",
  "<leader>xX",
  "<cmd>Trouble diagnostics toggle filter.buf=0<CR>",
  { desc = "Toggle diagnostics for current buffer" }
)
vim.keymap.set(
  "n",
  "<leader>xd",
  "<cmd>TroubleToggle document_diagnostics<CR>",
  { desc = "Toggle document diagnostics" }
)
vim.keymap.set("n", "<leader>xl", "<cmd>TroubleToggle loclist<CR>", { desc = "Toggle location list" })
vim.keymap.set("n", "<leader>xq", "<cmd>TroubleToggle quickfix<CR>", { desc = "Toggle quickfix list" })
vim.keymap.set("n", "gR", "<cmd>TroubleToggle lsp_references<CR>", { desc = "Toggle LSP references" })

-- Scrollfix
vim.keymap.set("n", "<F2>", "<cmd>FIX 25<CR>", { desc = "Set FIX to 25" })
vim.keymap.set("n", "<F0>", "<cmd>FIX -1<CR>", { desc = "Set FIX to -1" })

-- Obsidian
vim.keymap.set("v", "ol", ":ObsidianLink<CR>", { silent = false, desc = "Obsidian link" })
vim.keymap.set("n", "oq", ":ObsidianQuickSwitch<CR>", { desc = "Obsidian quick switch" })
vim.keymap.set("n", "on", ":ObsidianNew ", { silent = false, desc = "Obsidian new note" })
vim.keymap.set("v", "on", ":ObsidianLinkNew ", { silent = false, desc = "Obsidian link new" })
vim.keymap.set("n", "os", ":ObsidianSearch<CR>", { desc = "Obsidian search" })
vim.keymap.set("n", "ob", ":ObsidianBacklinks<CR>", { desc = "Obsidian backlinks" })
vim.keymap.set("n", "ot", ":ObsidianTags<CR>", { desc = "Obsidian tags" })
vim.keymap.set("n", "od", ":ObsidianToday<CR>", { desc = "Obsidian today" })

-- Copilot
vim.keymap.set("i", "<C-s>", 'copilot#Accept("<CR>")', { silent = true, expr = true })
vim.g.copilot_no_tab_map = true
vim.keymap.set("n", "<leader>cpd", ":Copilot disable<CR>", { desc = "Disable Copilot" })
vim.keymap.set("n", "<leader>cpe", ":Copilot enable<CR>", { desc = "Enable Copilot" })

-- GoTo Preview
vim.keymap.set(
  "n",
  "gtp",
  "<cmd>lua require('goto-preview').goto_preview_definition()<CR>",
  { desc = "Goto preview definition" }
)

-- Yank Matching Lines
vim.keymap.set("n", "<leader>ya", ":YankMatchingLines<CR>", { desc = "Yank matching lines" })

-- GpChat
local function keymapOptions(desc)
  return {
    noremap = true,
    silent = true,
    nowait = true,
    desc = "GPT prompt " .. desc,
  }
end

vim.keymap.set("n", "<leader>-", function()
  vim.fn.system "bash __restart_nvim.sh"
end, { desc = "Restart Neovim" })

vim.keymap.set({ "n", "i" }, "<C-g>r", "<cmd>GpRewrite<CR>", keymapOptions "Inline Rewrite")
vim.keymap.set({ "n", "i" }, "<C-g>a", "<cmd>GpAppend<CR>", keymapOptions "Append")
vim.keymap.set({ "n", "i" }, "<C-g>b", "<cmd>GpPrepend<CR>", keymapOptions "Prepend")
vim.keymap.set({ "n", "i" }, "<C-g>e", "<cmd>GpEnew<CR>", keymapOptions "Enew")
vim.keymap.set({ "n", "i" }, "<C-g>p", "<cmd>GpPopup<CR>", keymapOptions "Popup")
vim.keymap.set({ "n", "i" }, "<C-g>w", "<cmd>GpWhisper<CR>", keymapOptions "Whisper")
vim.keymap.set("v", "<C-g>r", ":<C-u>'<,'>GpRewrite<CR>", keymapOptions "Visual Rewrite")
vim.keymap.set("v", "<C-g>a", ":<C-u>'<,'>GpAppend<CR>", keymapOptions "Visual Append")
vim.keymap.set("v", "<C-g>b", ":<C-u>'<,'>GpPrepend<CR>", keymapOptions "Visual Prepend")
vim.keymap.set("v", "<C-g>e", ":<C-u>'<,'>GpEnew<CR>", keymapOptions "Visual Enew")
vim.keymap.set("v", "<C-g>p", ":<C-u>'<,'>GpPopup<CR>", keymapOptions "Visual Popup")
vim.keymap.set({ "n", "i", "v", "x" }, "<C-g>s", "<cmd>GpStop<CR>", keymapOptions "Stop")

-- NoNeckPain
vim.keymap.set("n", "<leader>ne", "<cmd>NoNeckPain<CR>", { desc = "Toggle NoNeckPain" })

-- Telescope Crossplane
vim.keymap.set(
  "n",
  "<leader>tcm",
  ":Telescope telescope-crossplane crossplane_managed<CR>",
  { desc = "Crossplane managed" }
)
vim.keymap.set(
  "n",
  "<leader>tcr",
  ":Telescope telescope-crossplane crossplane_resources<CR>",
  { desc = "Crossplane resources" }
)

-- Mini Files
vim.keymap.set("n", "<leader>mf", ":lua MiniFiles.open()<CR>", { desc = "Open MiniFiles" })

-- UndoTree
vim.keymap.set("n", "<leader>u", function()
  require("undotree").toggle()
end, { desc = "Toggle UndoTree" })

-- Send to Window
vim.keymap.set("x", "<leader><Left>", "<Plug>SendLeftV<CR>", { desc = "Send left" })
vim.keymap.set("x", "<leader><Down>", "<Plug>SendDownV<CR>", { desc = "Send down" })
vim.keymap.set("x", "<leader><Up>", "<Plug>SendUpV<CR>", { desc = "Send up" })
vim.keymap.set("x", "<leader><Right>", "<Plug>SendRightV<CR>", { desc = "Send right" })
vim.keymap.set("n", "<Left>", "<Plug>SendLeft", { desc = "Send left" })
vim.keymap.set("n", "<Down>", "<Plug>SendDown", { desc = "Send down" })
vim.keymap.set("n", "<Up>", "<Plug>SendUp", { desc = "Send up" })
vim.keymap.set("n", "<Right>", "<Plug>SendRight", { desc = "Send right" })

-- Toggle Inlay Hints
vim.keymap.set("n", "<leader>th", function()
  vim.lsp.inlay_hint(0, nil)
end, { desc = "Toggle inlay hints" })

-- Various Text Objects
vim.keymap.set(
  { "o", "x" },
  "ii",
  "<cmd>lua require('various-textobjs').indentation(true, true)<CR>",
  { desc = "Inner indentation" }
)
vim.keymap.set(
  { "o", "x" },
  "ai",
  "<cmd>lua require('various-textobjs').indentation(false, true)<CR>",
  { desc = "Around indentation" }
)
vim.keymap.set(
  { "o", "x" },
  "iI",
  "<cmd>lua require('various-textobjs').indentation(true, true)<CR>",
  { desc = "Inner indentation (lines)" }
)
vim.keymap.set(
  { "o", "x" },
  "aI",
  "<cmd>lua require('various-textobjs').indentation(false, false)<CR>",
  { desc = "Around indentation (lines)" }
)
