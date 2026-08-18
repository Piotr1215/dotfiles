-- ~/.config/nvim/lua/user_functions/registers.lua
local M = {}
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"

-- Pick a register from telescope and paste it over the visual selection.
function M.replace_with_register()
  require("telescope.builtin").registers {
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local content = action_state.get_selected_entry().content
        actions.close(prompt_bufnr)
        vim.fn.setreg("a", content)
        -- gv restores the selection the :lua mapping dropped
        vim.api.nvim_feedkeys('gv"ap', "n", false)
      end)
      return true
    end,
  }
end

vim.keymap.set(
  "x",
  "<leader>rg",
  [[:<C-u>lua require('user_functions.registers').replace_with_register()<CR>]],
  { noremap = true, silent = true, desc = "replace selection with register (picker)" }
)

return M
