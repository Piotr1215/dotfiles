local M = {}

local function map(mode, shortcut, command)
  vim.api.nvim_set_keymap(mode, shortcut, command, { noremap = true, silent = true })
end

function M.emap(shortcut, command)
  map('', shortcut, command)
end

--Leader normal mapping
function M.lnmap(shortcut, command)
  local leader = "<leader>" .. shortcut
  map('n', leader, command)
end

function M.nmap(shortcut, command)
  map('n', shortcut, command)
end

function M.imap(shortcut, command)
  map('i', shortcut, command)
end

function M.vmap(shortcut, command)
  map('v', shortcut, command)
end

function M.xmap(shortcut, command)
  map('x', shortcut, command)
end

function M.omap(shortcut, command)
  map('o', shortcut, command)
end

function M.smap(shortcut, command)
  map('s', shortcut, command)
end

function M.tmap(shortcut, command)
  map('t', shortcut, command)
end

return M
