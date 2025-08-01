local utils = require "utils"
local opts = { noremap = true, silent = true }
local shell = require "user_functions.shell_integration"
-- Load sensitive mappings
local s_mappings = require "s_mappings"

vim.keymap.set({ "n", "v" }, "<Space>", "<Nop>", { silent = true })
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Abbreviations
vim.cmd [[iabbrev gct Give me a command to]]
vim.cmd [[iabbrev ooc only one command]]

-- SAVE & CLOSE --
utils.lnmap("wa", ":wqa<cr>", { desc = "save and close all" })
utils.lnmap("wq", ":wq<cr>", { desc = "save and close all" })
utils.imap("jk", "<Esc>", { desc = "esc and save" })
utils.nmap("<leader>w", ":wall<CR>", { desc = "save all" })
utils.lnmap("qq", "@q", { desc = "close all" })
utils.lnmap("qa", ":qa!<cr>", { desc = "close all without saving" })
utils.lnmap("qf", ":q!<cr>", { desc = "close current bufferall without saving" })

vim.keymap.set(
  "n",
  "<leader>tf",
  ":!touch %<cr>",
  { silent = true, noremap = true, desc = "touch file to reload observers" }
)
utils.nmap("<nop>", "<Plug>NERDCommenterAltDelims") -- tab is for moving around only
utils.nmap("L", "vg_", { desc = "select to end of line" })

vim.keymap.set("n", "<leader>_", "5<c-w>-", { remap = true, silent = false })
vim.keymap.set("n", "<leader>+", "5<c-w>+", { remap = true, silent = false })

-- NAVIGATION --
-- Mappings for navigation between tmux and vim splits with the same keybindings
local nvim_tmux_nav = require "nvim-tmux-navigation"
vim.keymap.set("n", "<C-h>", nvim_tmux_nav.NvimTmuxNavigateLeft, { noremap = true, silent = true })
vim.keymap.set("n", "<C-j>", nvim_tmux_nav.NvimTmuxNavigateDown, { noremap = true, silent = true })
vim.keymap.set("n", "<C-k>", nvim_tmux_nav.NvimTmuxNavigateUp, { noremap = true, silent = true })
vim.keymap.set("n", "<C-l>", nvim_tmux_nav.NvimTmuxNavigateRight, { noremap = true, silent = true })
vim.keymap.set("n", "<A-m>", nvim_tmux_nav.NvimTmuxNavigateNext, { noremap = true, silent = true })
-- Toggle between single, double, and backtick quotes
vim.keymap.set("n", "<leader>tq", function()
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col "."
  local new_line = line:gsub("(['\"`])(.-[^\\])%1", function(q, content)
    if q == "'" then
      return '"' .. content .. '"'
    elseif q == '"' then
      return "`" .. content .. "`"
    else
      return "'" .. content .. "'"
    end
  end)
  vim.api.nvim_set_current_line(new_line)
  vim.fn.cursor(vim.fn.line ".", col)
end, { desc = "Toggle quote style" })
-- Insert mode mappings
vim.keymap.set(
  "i",
  "<C-h>",
  [[<C-\><C-N>:lua require("nvim-tmux-navigation").NvimTmuxNavigateLeft()<CR>]],
  { noremap = true, silent = true }
)
vim.keymap.set(
  "i",
  "<C-j>",
  [[<C-\><C-N>:lua require("nvim-tmux-navigation").NvimTmuxNavigateDown()<CR>]],
  { noremap = true, silent = true }
)
vim.keymap.set(
  "i",
  "<C-k>",
  [[<C-\><C-N>:lua require("nvim-tmux-navigation").NvimTmuxNavigateUp()<CR>]],
  { noremap = true, silent = true }
)
vim.keymap.set(
  "i",
  "<C-l>",
  [[<C-\><C-N>:lua require("nvim-tmux-navigation").NvimTmuxNavigateRight()<CR>]],
  { noremap = true, silent = true }
)
vim.keymap.set(
  "i",
  "<A-m>",
  [[<C-\><C-N>:lua require("nvim-tmux-navigation").NvimTmuxNavigateNext()<CR>]],
  { noremap = true, silent = true }
)
-- Terminal mode mappings
vim.keymap.set("t", "<C-h>", "<C-\\><C-n><C-h>", { noremap = true, silent = true })
vim.keymap.set("t", "<C-j>", "<C-\\><C-n><C-j>", { noremap = true, silent = true })
vim.keymap.set("t", "<C-k>", "<C-\\><C-n><C-k>", { noremap = true, silent = true })
vim.keymap.set("t", "<C-l>", "<C-\\><C-n><C-l>", { noremap = true, silent = true })
vim.keymap.set("t", "<A-m>", "<C-\\><C-n><A-m>", { noremap = true, silent = true })

utils.nmap("<c-u>", "<c-u>zz", { desc = "center screen after page up" })
utils.nmap("<c-d>", "<c-d>zz", { desc = "center screen after page down" })
vim.keymap.set({ "n", "v" }, "<A-j>", [[10j<cr>]], { desc = "moves over virtual (wrapped) lines down" })
vim.keymap.set({ "n", "v" }, "<A-k>", [[10k<cr>]], { desc = "moves over virtual (wrapped) lines up" })
vim.api.nvim_set_keymap(
  "n",
  "k",
  "v:count == 0 ? 'gk' : 'k'",
  { noremap = true, expr = true, silent = true, desc = "moves up over virtual (wrapped) lines" }
)
vim.api.nvim_set_keymap(
  "n",
  "j",
  "v:count == 0 ? 'gj' : 'j'",
  { noremap = true, expr = true, silent = true, desc = "moves down over virtual (wrapped) lines" }
)
vim.api.nvim_set_keymap("n", "<M-l>", "<cmd>tabnext<cr>", { noremap = true, silent = true, desc = "move to next tab" })
vim.api.nvim_set_keymap(
  "n",
  "<M-h>",
  "<cmd>tabprevious<cr>",
  { noremap = true, silent = true, desc = "move to next tab" }
)
utils.nmap("<BS>", "^", { desc = "move to first non-bkgtgtgtgtlank character of the line" })
utils.vmap("<S-PageDown>", ":m '>+1<CR>gv=gv", { desc = "Move Line Down in Visual Mode" })
utils.vmap("<S-PageUp>", ":m '<-2<CR>gv=gv", { desc = "Move Line Up in Visual Mode" })
utils.nmap("<leader>mk", ":m .-2<CR>==", { desc = "Move Line Up in Normal Mode" })
utils.nmap("<leader>mj", ":m .+1<CR>==", { desc = "Move Line Down in Normal Mode" })
utils.vmap("<leader>mk", ":m '<-2<CR>gv=gv", { desc = "Move Line Up in Visual Mode" })
utils.vmap("<leader>mj", ":m '>+1<CR>gv=gv", { desc = "Move Line Down in Visual Mode" })
utils.nmap("<Leader>em", ":/\\V\\c\\<\\>", { desc = "find exact match", silent = false })
vim.keymap.set("n", "J", "mzJ`z", { desc = "join lines without spaces" })
vim.keymap.set("n", "n", "nzzzv", { desc = "keep cursor centered" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "keep cursor centered" })
-- SEARCH AND REPLACE

utils.lnmap("sw", "viwP", { desc = "Substitute word (no cutting)" })
utils.lnmap("sw", "viwP", { desc = "Substitute word (no cutting)" })
utils.lnmap("sp", "vipP", { desc = "Substitute inner paragraph (no cutting)" })
utils.lnmap("sP", "vapP", { desc = "Substitute outer paragraph (no cutting)" })
utils.lnmap("pa", "ggVGP", { desc = "select all and paste (no cutting)" })
utils.lnmap("sa", "ggVG", { desc = "select all" })
utils.lnmap("ss", ":s/\\v", { silent = false, desc = "search and replace on line" })
utils.lnmap("SS", ":%s/\\v", { silent = false, desc = "search and replace in file" })
utils.vmap("<leader><C-s>", ":s/\\%V", { desc = "Search only in visual selection usingb%V atom" })
utils.vmap("<C-r>", '"hy:%s/\\v<C-r>h//g<left><left>', { silent = false, desc = "change selection" })
utils.nmap(",<space>", ":nohlsearch<CR>", { desc = "Stop search highlight" })
utils.nmap("<leader>x", "*``cgn", { desc = "replace word under cursor simultaneously" })
utils.nmap("<leader>X", "#``cgn", { desc = "replace word under cursor simultaneously" })
-- MACROS --
utils.xmap("<leader>Q", ":'<,'>:normal @q<CR>", { desc = "run macro from q register on visual selection" })
utils.tmap("<ESC>", "<C-\\><C-n>", { desc = "exit terminal mode" })
vim.keymap.set(
  "n",
  "<leader>ml",
  "^I-<Space>[<Space>]<Space><Esc>^j",
  { remap = true, silent = false, desc = "prepend markdown list item on line" }
)
utils.vmap("srt", ":!sort -n -k 2<cr>", { desc = "sort by second column" })
-- MANIPULATE TEXT --
utils.nmap("<leader>gp", "`[v`]", { desc = "select pasted text" })
utils.imap("<A-l>", "<C-o>a", { desc = "skip over a letter" })
utils.imap("<C-n>", "<C-e><C-o>A;<ESC>", { desc = "insert semicolon at the end of the line" })

-- Insert empty lines above and below
vim.keymap.set("n", "<leader>al", function()
  shell.add_empty_lines { below = true }
end, { remap = true, silent = false, desc = "Insert empty lines above" })
vim.keymap.set("n", "<leader>aL", function()
  shell.add_empty_lines { below = false }
end, { remap = true, silent = false, desc = "Insert empty lines below" })

-- Insert empty lines above and below
vim.keymap.set("n", "<leader>il", function()
  shell.add_empty_lines { below = true, insert = true }
end, { remap = true, silent = false, desc = "Insert empty lines above" })
vim.keymap.set("n", "<leader>iL", function()
  shell.add_empty_lines { below = false, insert = true }
end, { remap = true, silent = false, desc = "Insert empty lines below" })

utils.nmap("<leader>is", "i<space><esc>", { desc = "Insert space in normal mode" })
utils.nmap("<leader>sq", ':normal viWS"<CR>', { desc = "surround with quotation" })
utils.nmap("<leader>s`", ":normal viWS`<CR>", { desc = "surround with backticks" })
-- REGISTRIES --

vim.keymap.set("i", "<c-p>", function()
  require("telescope.builtin").registers()
end, {
  remap = true,
  silent = false,
  desc = " and paste register in insert mode",
})

utils.lnmap("yl", '"*yy', { desc = "yank line to the clipboard buffer" })
utils.nmap("<leader>df", ":%d<cr>", { desc = "delete file content to black hole register" })
utils.nmap("<leader>yf", ":%y<cr>", { desc = "yank file under cusror to the clipboard buffer" })
utils.nmap("<leader>yw", '"+yiw', { desc = "yank word under cusror to the clipboard buffer" })
utils.nmap("<leader>yW", '"+yiW', { desc = "yank WORD under cusror to the clipboard buffer" })
utils.lnmap("p", '"*P', { desc = "paste from clipboard buffer before the cursor" })
utils.nmap("<leader>0", '"0p', { desc = "paste from 0 (latest yank)" })
utils.nmap("<leader>1", '"1p', { desc = "paste from 1 (latest delete)" })
utils.nmap("<leader>2", '"*p', { desc = "paste from 2 (clipboard)" })
utils.nmap("<Leader>p", ":pu<CR>", { desc = "paste from clipboard buffer after the cursor" })
utils.lnmap("dl", '"_dd', { desc = "delete line to black hole register" })
utils.lnmap("d_", '"_D', { desc = "delete till end of line to black hole register" })
utils.xmap("<leader>d", '"_d', { desc = "delete selection to black hole register" })

-- FILE NAVIGATION --
vim.keymap.set("n", "gF", "<C-w>vgf", { desc = "Open file under cursor in vertical split" })

-- PATH OPERATIONS --
vim.keymap.set(
  "n",
  "<leader>cpf",
  ':let @+ = expand("%:p")<cr>:lua print("Copied path to: " .. vim.fn.expand("%:p"))<cr>',
  { desc = "Copy current file name and path", silent = false }
)
vim.keymap.set(
  "n",
  "<leader>cpl",
  ':let @+ = expand("%:p").":".line(".")<cr>:lua print("Copied file name: " .. vim.fn.expand("%:t"))<cr>',
  { desc = "Copy current file name", silent = false }
)

vim.api.nvim_set_keymap(
  "n",
  "<leader>eb",
  [[:lua require('user_functions.shell_integration').run_cmd_in_backticks()<CR>]],
  { noremap = true, silent = true }
)

vim.api.nvim_set_keymap(
  "n",
  "<leader>yb",
  [[:lua require('user_functions.shell_integration').copy_last_backticks()<CR>]],
  { noremap = true, silent = true }
)

vim.api.nvim_set_keymap(
  "v",
  "<leader>eb",
  [[:lua require('user_functions.shell_integration').run_cmd_for_selection()<CR>]],
  { noremap = true, silent = true }
)

vim.api.nvim_set_keymap(
  "v",
  "<leader>eB",
  [[:lua require('user_functions.shell_integration').run_cmd_block()<CR>]],
  { noremap = true, silent = true }
)

vim.keymap.set("n", "<leader>rc", "?```<CR>k eb<c-g><c-g>", { remap = true, silent = false })

utils.lnmap("cpl", [[:let @+ = expand("%:p") . ':' . line('.')<cr>]]) -- Copy current file name, path, and line number
utils.lnmap("cpn", ':let @+ = expand("%:t")<cr>') -- Copy current file name
utils.imap("<c-d>", "<c-o>daw", { desc = "delete word forward in insert mode" })
vim.keymap.set("i", "<A-H>", "<c-w>", { noremap = true, desc = "delete word forward in insert mode" })
vim.keymap.set("i", "<A-,>", "<c-o>A,<c-o>o", { noremap = true, desc = "add coma and enter new line under" })
utils.nmap("<leader>sl", "i<cr><esc>", { desc = "split line in two" })
-- EXTERNAL COMMANDS --
vim.keymap.set("c", "<C-w>", "\\w*", { noremap = true, desc = "copy word under cursor" })
vim.keymap.set("c", "<C-s>", "\\S*", { noremap = true, desc = "copy WORD under cursor" })
utils.nmap("<leader>ex", ":.w !bash -e <cr>", { desc = "execute current line and output to command line" })
utils.nmap("<leader>eX", ":%w !bash -e <cr>", { desc = "exexute all lines and output to command line" })
utils.nmap("<leader>el", ":.!bash -e <cr>", { silent = false, desc = "execute current line and replace with result" })
utils.nmap("<leader>eL", ":% !bash % <cr>", { desc = "execute all lines and replace with result" })
utils.lnmap("cx", ":!chmod +x %<cr>", { desc = "make file executable" })
utils.lnmap(
  "ef",
  "<cmd>lua require('user_functions.shell_integration').execute_file_and_show_output()<CR>",
  { silent = false }
) -- execute file and show output
utils.vmap("<Leader>pb", "w !bash share<CR>") -- upload selected to ix.io
-- FORMATTING --
utils.nmap("<leader>fmt", ":Pretty<CR>") -- format json with pretty
-- SPELLING --
utils.nmap("<Leader>son", ":setlocal spell spelllang=en_us<CR>") -- set spell check on
utils.nmap("<Leader>sof", ":set nospell<CR>") -- set spell check off
-- GIT RELATED --
vim.keymap.set({ "n", "v" }, "<leader>gbf", ":GBrowse<cr>", opts) -- git browse current file in browser
vim.keymap.set("n", "<leader>gbc", function()
  vim.cmd "GBrowse!"
end, { desc = "Copy url to current file" }) -- git browse current file and line in browser
vim.keymap.set("v", "<leader>gbl", ":GBrowse!<CR>", { noremap = true, silent = false }) -- git browse current file and selected line in browser
utils.lnmap("gd", ":Gvdiffsplit<CR>") -- git diff current file
utils.lnmap("gu", ":Gdiffu<CR>") -- git diff current file
utils.nmap("<leader>gl", ":r !bash ~/dev/dotfiles/scripts/__generate_git_log.sh<CR>") -- generate git log
utils.lnmap("gh", ":Gclog %<CR>") -- show git log for current file
-- PROGRAMMING --
-- LuaSnip mappings are handled in lua/config/luasnip.lua
-- <M-l> for expand_or_jump, <M-h> for jump back, <M-j> for choice selection

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

-- Trouble
vim.keymap.set("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>xd", "<cmd>TroubleToggle document_diagnostics<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>xl", "<cmd>TroubleToggle loclist<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "<leader>xq", "<cmd>TroubleToggle quickfix<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "gR", "<cmd>TroubleToggle lsp_references<cr>", { silent = true, noremap = true })

-- Scrollfix
utils.lnmap("f2", "<cmd>FIX 35<cr>")
utils.lnmap("f0", "<cmd>FIX -1<cr>")

-- Obsidian
utils.vmap("ol", ":ObsidianLink<cr>", { silent = false })
utils.lnmap("ol", ":ObsidianLinks<cr>", { silent = false })
utils.lnmap("oq", ":ObsidianQuickSwitch<cr>")
utils.lnmap("on", ":ObsidianNew ", { silent = false })
utils.vmap("on", ":ObsidianLinkNew ", { silent = false })
utils.lnmap("os", ":ObsidianSearch<cr>")
utils.lnmap("ob", ":ObsidianBacklinks<cr>")
utils.lnmap("ot", ":ObsidianTags<cr>")
utils.lnmap("od", ":ObsidianToday<cr>")

-- Copilot
vim.cmd [[
        imap <silent><script><expr> <C-s> copilot#Accept("\<CR>")
        let g:copilot_no_tab_map = v:true
]]
utils.lnmap("cpd", ":Copilot disable<cr>", { silent = false })
utils.lnmap("cpe", ":Copilot enable<cr>", { silent = false })
vim.keymap.set("i", "<M-w>", "<Plug>(copilot-accept-word)")

-- CopilotChat
utils.nmap("<leader>cc", ":CopilotChatToggle<CR>", { desc = "Toggle Copilot Chat" })

-- GoTo Preview
vim.keymap.set("n", "gtp", "<cmd>lua require('goto-preview').goto_preview_definition()<CR>", { noremap = true })

-- Yank Matching Lines
vim.api.nvim_set_keymap("n", "<Leader>ya", ":YankMatchingLines<CR>", { noremap = true, silent = true })

-- GpChat gp.nvim
local function keymapOptions(desc)
  return {
    noremap = true,
    silent = true,
    nowait = true,
    desc = "GPT prompt " .. desc,
  }
end

local function switch(agent)
  -- :GpAgent <name> picks chat- or command-scope automatically,
  -- depending on the buffer you’re in :contentReference[oaicite:0]{index=0}
  vim.cmd("GpAgent " .. agent)
end

-- <leader>a i c   →  Claude-3.7  (your “default”)
vim.keymap.set("n", "<leader>aic", function()
  switch "Claude4"
end, { desc = "gp.nvim: use Claude-4 (Anthropic)" })

-- <leader>a i o   →  GPT-4-o / o3-mini (OpenAI)
vim.keymap.set("n", "<leader>aio", function()
  switch "o3-mini"
end, { desc = "gp.nvim: use o3-mini (OpenAI)" })

vim.keymap.set("n", "<leader>aig", function()
  switch "ChatGPT4.1"
end, { desc = "gp.nvim: use GPT-4.1 (OpneAI)" })

-- <leader>a i p   →  Perplexity (sonar model)
vim.keymap.set("n", "<leader>aip", function()
  switch "pplx"
end, { desc = "gp.nvim: use Perplexity (sonar)" })

-- Restart nvim
vim.keymap.set("n", "<leader>-", function()
  vim.fn.system "bash __restart_nvim.sh"
end, { noremap = true, silent = true })

vim.keymap.set({ "n", "i" }, "<C-g><C-w>w", "<cmd>GpWhisper<cr>", keymapOptions "Whisper Insert")
vim.keymap.set({ "n", "i" }, "<C-g>r", "<cmd>GpRewrite<cr>", keymapOptions "Inline Rewrite")
vim.keymap.set({ "n", "i" }, "<C-g><C-w>r", "<cmd>GpWhisperRewrite<cr>", keymapOptions "Whisper Rewrite")
vim.keymap.set({ "n", "i" }, "<C-g>a", "<cmd>GpAppend<cr>", keymapOptions "Append")
vim.keymap.set({ "n", "i" }, "<C-g>b", "<cmd>GpPrepend<cr>", keymapOptions "Prepend")
vim.keymap.set({ "n", "i" }, "<C-g>e", "<cmd>GpEnew<cr>", keymapOptions "Enew")
vim.keymap.set({ "n", "i" }, "<C-g>p", "<cmd>GpPopup<cr>", keymapOptions "Popup")
vim.keymap.set({ "n", "i" }, "<C-g><C-w>a", "<cmd>GpWhisperAppend<cr>", keymapOptions "Whisper Append")
vim.keymap.set({ "n", "i" }, "<C-g><C-w>b", "<cmd>GpWhisperPrepend<cr>", keymapOptions "Whisper Prepend")
vim.keymap.set({ "n", "i" }, "<C-g><C-w>e", "<cmd>GpWhisperEnew<cr>", keymapOptions "Whisper Enew")
vim.keymap.set({ "n", "i" }, "<C-g><C-w>p", "<cmd>GpWhisperPopup<cr>", keymapOptions "Whisper Popup")
vim.keymap.set({ "n" }, "<C-g>w", ":GpWebSearch ", keymapOptions "Vnew")
vim.keymap.set({ "n" }, "<C-g>f", "<cmd>GpChatFinder<cr>", keymapOptions "Find Chats")
vim.keymap.set("v", "<C-g>r", ":<C-u>'<,'>GpRewrite<cr>", keymapOptions "Visual Rewrite")
vim.keymap.set("v", "<C-g><C-w>r", ":<C-u>'<,'>GpWhisperRewrite<cr>", keymapOptions "Visual Whisper Rewrite")
vim.keymap.set("v", "<C-g><C-w>r", ":<C-u>'<,'>GpWhisperRewrite<cr>", keymapOptions "Visual Whisper Rewrite")
vim.keymap.set("v", "<C-g><C-w>c", ":<C-u>'<,'>GpWhisperChatPaste<cr>", keymapOptions "Visual Whisper Chat Paste")
vim.keymap.set("v", "<C-g><C-w>a", ":<C-u>'<,'>GpWhisperAppend<cr>", keymapOptions "Visual Whisper Append")
vim.keymap.set("v", "<C-g><C-w>b", ":<C-u>'<,'>GpWhisperPrepend<cr>", keymapOptions "Visual Whisper Prepend")
vim.keymap.set("v", "<C-g><C-w>e", ":<C-u>'<,'>GpWhisperEnew<cr>", keymapOptions "Visual Whisper Enew")
vim.keymap.set("v", "<C-g><C-w>p", ":<C-u>'<,'>GpWhisperPopup<cr>", keymapOptions "Visual Whisper Popup")
vim.keymap.set("v", "<C-g>w", ":<C-u>'<,'>GpWebSearchSelection<cr>", keymapOptions "Visual Web Search")
vim.keymap.set("v", "<C-g>c", ":<C-u>'<,'>GpChatPaste<cr>", keymapOptions "Visual Chat Paste")
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
vim.keymap.set("n", "<leader>uo", "<Cmd>UrlView<CR>", { desc = "View buffer URLs" })
vim.keymap.set("n", "<leader>Uo", "<Cmd>UrlView lazy<CR>", { desc = "View Packer plugin URLs" })

vim.keymap.set("n", "<leader>th", function()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end, { silent = true, noremap = true, desc = "Toggle inlay hints" })
-- Various text objects plugin mappings

vim.keymap.set({ "o", "x" }, "ii", "<cmd>lua require('various-textobjs').indentation('inner', 'inner')<CR>")
vim.keymap.set({ "o", "x" }, "ai", "<cmd>lua require('various-textobjs').indentation('outer', 'inner')<CR>")
vim.keymap.set({ "o", "x" }, "iI", "<cmd>lua require('various-textobjs').indentation('inner', 'inner')<CR>")
vim.keymap.set({ "o", "x" }, "aI", "<cmd>lua require('various-textobjs').indentation('outer', 'outer')<CR>")

-- Disable the specific keybinding in normal and visual mode
vim.api.nvim_set_keymap("n", "<Space>a", "<Nop>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<Space>a", "<Nop>", { noremap = true, silent = true })

-- Docusaurus key bindings
vim.keymap.set("n", "<leader>ic", "<cmd>DocusaurusInsertComponent<cr>", { desc = "Insert Docusaurus Component" })
vim.keymap.set("n", "<leader>ip", "<cmd>DocusaurusInsertPartial<cr>", { desc = "Insert Docusaurus Partial" })
vim.keymap.set("n", "<leader>ib", "<cmd>DocusaurusInsertCodeBlock<cr>", { desc = "Insert Docusaurus CodeBlock" })
vim.keymap.set("n", "<leader>iu", "<cmd>DocusaurusInsertURL<cr>", { desc = "Insert Docusaurus URL Reference" })

-- Decide there to autofill mapping based on space location
vim.cmd [[
     function! s:check_back_space() abort
       let col = col('.') - 1
       return !col || getline('.')[col - 1]  =~# '\s'
     endfunction
     ]]
