-- PlantUML ftplugin

-- Buffer settings
vim.opt_local.wrap = false
vim.opt_local.conceallevel = 0

-- Essential keymaps (localleader = \ by default)
local opts = { buffer = true, silent = true }

vim.keymap.set("n", "<localleader>o", "<cmd>PlantumlOpen<cr>", vim.tbl_extend("force", opts, { desc = "Open preview" }))

vim.keymap.set("n", "<localleader>s", function()
  vim.cmd "PlantumlSave"
  local png_path = vim.fn.expand "%:r" .. ".png"
  vim.fn.system { "xdg-open", png_path }
end, vim.tbl_extend("force", opts, { desc = "Save PNG and open" }))

vim.keymap.set("n", "<localleader>x", "<cmd>PlantumlStop<cr>", vim.tbl_extend("force", opts, { desc = "Stop file watcher" }))

-- Other commands (use via :):
-- :PumlRender      - Render SVG to ./rendered/ and open
