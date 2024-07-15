local wk = require "which-key"

wk.register({
  ["<leader>f"] = { name = "file" },
  ["<leader>fe"] = { "Edit File" },
  ["<leader>ff"] = { "Find File" },
  ["<leader>fn"] = { "New File" },
  ["<leader>fr"] = { "Open Recent File", remap = true },
}, { prefix = "<leader>" })
