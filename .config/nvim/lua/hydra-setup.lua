local Hydra = require("hydra")

Hydra({
  name = "Change / Resize Window",
  mode = { "n" },
  body = "<C-w>",
  config = {
    -- color = "pink",
  },
  heads = {
    -- move between windows
    { "<C-h>", "<C-w>h" },
    { "<C-j>", "<C-w>j" },
    { "<C-k>", "<C-w>k" },
    { "<C-l>", "<C-w>l" },

    -- resizing window
    { "H", "<C-w>3<" },
    { "L", "<C-w>3>" },
    { "K", "<C-w>2+" },
    { "J", "<C-w>2-" },

    -- equalize window sizes
    { "e", "<C-w>=" },

    -- close active window
    { "Q", ":q<cr>" },
    { "<C-q>", ":q<cr>" },

    -- exit this Hydra
    { "q", nil, { exit = true, nowait = true } },
    { ";", nil, { exit = true, nowait = true } },
    { "<Esc>", nil, { exit = true, nowait = true } },
  },
})

