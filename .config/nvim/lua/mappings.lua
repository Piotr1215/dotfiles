vim.g.mapleader = " "

function map(mode, shortcut, command)
  vim.api.nvim_set_keymap(mode, shortcut, command, { noremap = true, silent = true })
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

-- MOVE AROUND --
vmap("<S-PageDown>", ":m '>+1<CR>gv=gv")     -- Move Line Down in Visual Mode
vmap("<S-PageUp>", ":m '<-2<CR>gv=gv")       -- Move Line Up in Visual Mode
nmap("<leader>k", ":m .-2<CR>==")            -- Move Line Up in Normal Mode
nmap("<leader>j", ":m .+1<CR>==")            -- Move Line Down in Normal Mode

nmap("<Leader>nh", ":.,/^#/<CR>")            -- Got to next markdown header

-- SEARCH & REPLACE --
-- Easy Motion Mappings
nmap("<Leader>o", "<Plug>(easymotion-prefix)")
nmap("<Leader>of", "<Plug>(easymotion-bd-f)")
nmap("<Leader>ol", "<Plug>(easymotion-bd-w)")
nmap("<Leader>oc", "<Plug>(easymotion-overwin-f2)")
-- Stop search highlight
nmap(",<space>", ":nohlsearch<CR>")
vmap("<C-r>", '"hy:%s/<C-r>h//gc<left><left><left>')

-- MACROS --
nmap("<Leader>q", "@q")
xmap("Q", ":'<,'>:normal @q<CR>")

