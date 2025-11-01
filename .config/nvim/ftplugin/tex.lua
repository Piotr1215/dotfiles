-- VimTeX which-key integration
-- Register VimTeX keybindings with which-key so they show up in the menu

local wk = require "which-key"

-- Register VimTeX keybindings with which-key
wk.add {
  { "\\", group = "VimTeX", buffer = 0 },
  { "\\l", group = "VimTeX", buffer = 0 },
  { "\\ll", desc = "Toggle continuous compilation", buffer = 0 },
  { "\\lv", desc = "View PDF", buffer = 0 },
  { "\\lc", desc = "Clean auxiliary files", buffer = 0 },
  { "\\lC", desc = "Clean full", buffer = 0 },
  { "\\lk", desc = "Stop compilation", buffer = 0 },
  { "\\lK", desc = "Stop all", buffer = 0 },
  { "\\le", desc = "Open quickfix errors", buffer = 0 },
  { "\\lo", desc = "Show compiler output", buffer = 0 },
  { "\\lg", desc = "Compilation status", buffer = 0 },
  { "\\lG", desc = "Show all compilation status", buffer = 0 },
  { "\\lt", desc = "Open table of contents", buffer = 0 },
  { "\\lT", desc = "Toggle table of contents", buffer = 0 },
  { "\\li", desc = "Show info", buffer = 0 },
  { "\\lI", desc = "Show full info", buffer = 0 },
  { "\\lm", desc = "Show imaps", buffer = 0 },
  { "\\lx", desc = "Reload VimTeX", buffer = 0 },
  { "\\lX", desc = "Reload VimTeX state", buffer = 0 },
  { "\\ls", desc = "Toggle main file", buffer = 0 },
  { "\\la", desc = "Show context menu", buffer = 0 },
}
