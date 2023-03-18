local M = {}

local function map(mode, shortcut, command, options)
  local default_options = { noremap = true, silent = true }
  local merged_options = options and vim.tbl_extend('force', default_options, options) or default_options
  vim.api.nvim_set_keymap(mode, shortcut, command, merged_options)
end

function M.emap(shortcut, command)
  map('', shortcut, command)
end

--Leader normal mapping
function M.lnmap(shortcut, command, options)
  local leader = "<leader>" .. shortcut
  map('n', leader, command, options)
end

function M.nmap(shortcut, command, options)
  map('n', shortcut, command, options)
end

function M.imap(shortcut, command, options)
  map('i', shortcut, command, options)
end

function M.vmap(shortcut, command, options)
  map('v', shortcut, command, options)
end

function M.xmap(shortcut, command, options)
  map('x', shortcut, command, options)
end

function M.omap(shortcut, command, options)
  map('o', shortcut, command, options)
end

function M.smap(shortcut, command, options)
  map('s', shortcut, command, options)
end

function M.tmap(shortcut, command, options)
  map('t', shortcut, command, options)
end

return M
