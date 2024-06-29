require "plugins"
require "settings"
require "autocommands"
require "mappings"
require "telescope-setup"
require "lsp"
-- require("lsp-setup")
require "which-key-setup"
require "user_functions"
require "projects"

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
