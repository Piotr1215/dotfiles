-- Set leader BEFORE lazy.nvim loads (required for keys in plugin specs)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- 0.12 ui2: redesigned message/cmdline UI. Kills "Press ENTER", highlights the
-- cmdline as you type, makes messages/pager real buffers (g< reopens history).
-- Experimental: lives in the vim._core.* namespace, so pcall-guard it to keep
-- startup alive if a future release renames or removes the module.
pcall(function()
  require("vim._core.ui2").enable {}
end)

require "plugins"
require "settings"
require "autocommands"
require "mappings"
require "telescope-setup"
require "lsp"

-- Load custom modules
require "custom-completions"
for _, file in ipairs(vim.fn.readdir(vim.fn.stdpath "config" .. "/lua/user_functions", [[v:val =~ '\.lua$']])) do
  require("user_functions." .. file:gsub("%.lua$", ""))
end

-- PROJECT: project-config
-- Searches for a .nvimrc file from the current directory up to the root and executes it if found.
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*",
  callback = function()
    local project_config_path = vim.fn.findfile(".nvimrc", ".;")
    if project_config_path ~= "" then
      loadfile(project_config_path)()
    end
  end,
})
