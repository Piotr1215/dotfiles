-- ~/.config/nvim/lua/user_functions/grep_project.lua
local M = {}

function M.grepInProject()
  local handle = io.popen "git rev-parse --show-toplevel 2> /dev/null"
  local gitRoot = handle and handle:read "*a" or ""
  if handle then
    handle:close()
  end

  if gitRoot ~= "" then
    gitRoot = gitRoot:gsub("%s+$", "")
  end

  local cwd = gitRoot ~= "" and gitRoot or vim.fn.getcwd()
  require("telescope").extensions.live_grep_args.live_grep_args { cwd = cwd }
end

vim.keymap.set("n", "<leader>fw", M.grepInProject, { noremap = true, silent = true })

return M
