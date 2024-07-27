-- ~/.config/nvim/lua/user_functions/registers.lua
local M = {}

function M.operator_callback()
  local s_pos = vim.fn.getpos "'<"
  local e_pos = vim.fn.getpos "'>"
  local s_line, s_col = s_pos[2], s_pos[3]
  local e_line, e_col = e_pos[2], e_pos[3]
  local register_content = vim.fn.getreg "a" -- Get the content of the "a" register

  -- Split the register content into lines
  local replacement_lines = vim.split(register_content, "\n")

  -- Replace the visually selected text with the lines from the register
  vim.api.nvim_buf_set_text(0, s_line - 1, s_col - 1, e_line - 1, e_col, replacement_lines)
end

function M.replace_with_register()
  print "Running replace_with_register function"
  -- Call the register picker from telescope
  require("telescope.builtin").registers {
    attach_mappings = function(prompt_bufnr, map)
      print "Register picker called from telescope"
      actions.select_default:replace(function()
        print "Inside actions.select_default:replace function"
        -- Close the picker
        actions.close(prompt_bufnr)
        print "Picker closed"

        -- Get the selected register
        local selection = action_state.get_selected_entry()
        print(vim.inspect(selection))

        -- Get the content of the selected register
        local register_content = selection.content
        print(vim.inspect(register_content))

        -- Set the content of the "a" register
        vim.fn.setreg("a", register_content)

        -- Set up the operator callback
        vim.o.operatorfunc = "v:lua._G.operator_callback"
        vim.api.nvim_feedkeys("g@`<", "ni", false) -- This triggers the operator callback on the visual selection

        print "Substitute command executed"
      end)
      print "Exited from actions.select_default:replace function"
      return true -- Keep the rest of the mappings
    end,
  }
end

-- Create a keymap to call the replace_with_register function
vim.api.nvim_set_keymap(
  "v",
  "<leader>rg",
  [[:lua require('user_functions.registers').replace_with_register()<CR>]],
  { noremap = true, silent = true }
)

return M
