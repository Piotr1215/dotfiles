vim.g.mapleader = " "

function map(mode, shortcut, command)
  vim.api.nvim_set_keymap(mode, shortcut, command, { noremap = true, silent = true })
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

vmap("<S-PageDown>", ":m '>+1<CR>gv=gv")
vmap("<S-PageUp>", ":m '<-2<CR>gv=gv")
imap("<C-j>", "<esc>:m .+1<CR>==")
imap("<C-k>", "<esc>:m .-2<CR>==")
map("<leader>k", ":m .-2<CR>==")
map("<leader>j", ":m .+1<CR>==")
map("<Leader>nh", ":.,/^#/<CR>")

