-- ~/.config/nvim/lua/user_functions/obsidian_notes.lua
local M = {}

function M.select_note_type_and_create()
  local note_types = {
    "projects",
    "areas",
    "resources",
    "meetings",
    "reviews",
  }

  vim.ui.select(note_types, { prompt = "Select note type:" }, function(choice)
    if not choice then
      return
    end
    local note_title = vim.fn.input "Note title: "
    if note_title ~= "" then
      -- Directly concatenate without additional quotes
      vim.cmd("CreateNoteWithTemplate " .. choice .. " " .. note_title)
    end
  end)
end

function M.create_note_with_template(template_type, note_title)
  -- Define base directory for notes
  local base_dir = "Notes"
  -- Define the command to create a new note using ObsidianNew
  local obsidian_new_cmd = string.format(":ObsidianNew %s/%s/%s", base_dir, template_type, note_title)
  vim.api.nvim_command(obsidian_new_cmd)

  -- Wait briefly to ensure command execution completion
  vim.wait(100, function() end)

  -- Insert two empty lines at the end
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "", "" })

  -- Move the cursor to the last line of the file
  vim.api.nvim_command "normal G"

  -- Apply the template based on the type
  local obsidian_template_cmd = string.format(":ObsidianTemplate %s.md", template_type)
  vim.api.nvim_command(obsidian_template_cmd)
end

vim.api.nvim_set_keymap(
  "n",
  "<leader>oc",
  ":lua require('user_functions.obsidian_notes').select_note_type_and_create()<CR>",
  { noremap = true, silent = true }
)

vim.api.nvim_create_user_command("CreateNoteWithTemplate", function(input)
  -- Split input to get template type and note title
  local args = vim.split(input.args, " ", { trimempty = true })
  if #args < 2 then
    print "Usage: CreateNoteWithTemplate <template_type> <note_title>"
    return
  end
  local template_type = args[1]
  local note_title = table.concat({ select(2, unpack(args)) }, " ")
  M.create_note_with_template(template_type, note_title)
end, { nargs = "+" })

return M
