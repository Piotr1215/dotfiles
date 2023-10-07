local module = require("projects.module")

-- main module file
local M = {}

-- setup is the public method to setup your plugin
M.setup = function(args)
  -- you can define your setup function here. Usually configurations can be merged, accepting outside params and
  -- you can also put some validation here for those.
  -- M.config = vim.tbl_deep_extend("force", M.config, args or {})
end

return M
