local set = vim.opt

-- This makes is so that o doesn't add comment and a regular newline
set.formatoptions:remove "o"

-- Show whitespace characters when :set list is enabled
set.listchars = { tab = "> ", space = "·", trail = "-", nbsp = "+" }
