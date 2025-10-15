-- ~/.config/nvim/lua/user_functions/obsidian_notes.lua
local M = {}

function M.select_note_type_and_create()
  local note_types = {
    "projects",
    "areas",
    "resources",
    "meetings",
    "reviews",
    "moc",
  }

  vim.ui.select(note_types, { prompt = "Select note type:" }, function(choice)
    if not choice then
      return
    end

    -- MOC has special handling (no MOC selection needed)
    if choice == "moc" then
      local note_title = vim.fn.input "MOC name (e.g., 'Security'): "
      if note_title ~= "" then
        M.create_moc_from_template(note_title)
      end
    else
      local note_title = vim.fn.input "Note title: "
      if note_title ~= "" then
        M.select_moc_and_create(choice, note_title)
      end
    end
  end)
end

function M.select_moc_and_create(note_type, note_title)
  local mocs = {
    "DevOps-MOC",
    "Development-MOC",
    "MCP-Framework-MOC",
    "Tools-MOC",
    "Homelab-MOC",
    "Personal-MOC",
    "(Skip - no MOC)",
  }

  vim.ui.select(mocs, { prompt = "Add to which MOC?" }, function(moc_choice)
    if not moc_choice then
      return
    end

    vim.cmd("CreateNoteWithTemplate " .. note_type .. " " .. note_title .. " " .. (moc_choice or ""))
  end)
end

-- Create a new MOC from template with given name
function M.create_moc_from_template(moc_name)
  -- Add -MOC suffix if not present
  if not moc_name:match "-MOC$" then
    moc_name = moc_name .. "-MOC"
  end

  -- Create MOC file in _mocs directory
  local moc_path = "Notes/_mocs/" .. moc_name
  vim.cmd("Obsidian new " .. moc_path)

  vim.wait(100, function() end)

  -- Insert two empty lines at the end
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "", "" })

  -- Move the cursor to the last line of the file
  vim.api.nvim_command "normal G"

  -- Apply the MOC template
  vim.api.nvim_command ":Obsidian template moc.md"

  vim.notify("✓ Created " .. moc_name .. " - Don't forget to add it to 00-INDEX.md!", vim.log.levels.INFO)
end

-- Find section headers in MOC file
local function find_sections(lines, section)
  local section_line = -1
  local related_areas_line = -1

  for i, line in ipairs(lines) do
    if line == "## " .. section then
      section_line = i
    end
    if line == "## Related Areas" then
      related_areas_line = i
    end
  end

  return section_line, related_areas_line
end

-- Find last bullet point in a section
local function find_last_bullet(lines, section_line)
  local last_bullet_line = section_line
  local next_section_line = #lines + 1

  -- Find next section
  for i = section_line + 1, #lines do
    if lines[i]:match "^## " then
      next_section_line = i
      break
    end
  end

  -- Find last bullet in current section
  for i = section_line + 1, next_section_line - 1 do
    if lines[i]:match "^%- " then
      last_bullet_line = i
    end
  end

  return last_bullet_line
end

-- Create new section with entry
local function create_section(lines, related_areas_line, section, new_entry)
  local new_lines = {}

  if related_areas_line ~= -1 then
    -- Insert before Related Areas
    for i, line in ipairs(lines) do
      if i == related_areas_line then
        table.insert(new_lines, "## " .. section)
        table.insert(new_lines, "")
        table.insert(new_lines, new_entry)
        table.insert(new_lines, "")
      end
      table.insert(new_lines, line)
    end
  else
    -- Append to end
    new_lines = vim.list_extend({}, lines)
    table.insert(new_lines, "")
    table.insert(new_lines, "## " .. section)
    table.insert(new_lines, "")
    table.insert(new_lines, new_entry)
    table.insert(new_lines, "")
  end

  return new_lines
end

-- Insert entry after last bullet in section
local function insert_after_bullet(lines, last_bullet_line, new_entry)
  local new_lines = {}

  for i, line in ipairs(lines) do
    table.insert(new_lines, line)
    if i == last_bullet_line then
      table.insert(new_lines, new_entry)
    end
  end

  return new_lines
end

-- Append note to MOC file (pure Lua implementation)
function M.append_to_moc(moc_name, note_title, section)
  section = section or "Related Projects"

  local vault_path = vim.fn.expand "~" .. "/dev/obsidian"
  local moc_file = vault_path .. "/decoder/Notes/_mocs/" .. moc_name .. ".md"

  if vim.fn.filereadable(moc_file) ~= 1 then
    vim.notify(string.format("✗ MOC file not found: %s", moc_file), vim.log.levels.ERROR)
    return false
  end

  -- Read file
  local lines = {}
  for line in io.lines(moc_file) do
    table.insert(lines, line)
  end

  local section_line, related_areas_line = find_sections(lines, section)
  local new_entry = "- [[" .. note_title .. "]] - "
  local new_lines

  if section_line == -1 then
    new_lines = create_section(lines, related_areas_line, section, new_entry)
  else
    local last_bullet_line = find_last_bullet(lines, section_line)
    new_lines = insert_after_bullet(lines, last_bullet_line, new_entry)
  end

  -- Write file
  local file = io.open(moc_file, "w")
  if not file then
    vim.notify(string.format("✗ Failed to write to %s", moc_file), vim.log.levels.ERROR)
    return false
  end

  for _, line in ipairs(new_lines) do
    file:write(line .. "\n")
  end
  file:close()
  return true
end

function M.create_note_with_template(template_type, note_title, moc_name)
  -- Define base directory for notes
  local base_dir = "Notes"
  -- Define the command to create a new note using Obsidian new
  local obsidian_new_cmd = string.format(":Obsidian new %s/%s/%s", base_dir, template_type, note_title)
  vim.api.nvim_command(obsidian_new_cmd)

  -- Wait briefly to ensure command execution completion
  vim.wait(100, function() end)

  -- Insert two empty lines at the end
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "", "" })

  -- Move the cursor to the last line of the file
  vim.api.nvim_command "normal G"

  -- Apply the template based on the type
  local obsidian_template_cmd = string.format(":Obsidian template %s.md", template_type)
  vim.api.nvim_command(obsidian_template_cmd)

  -- If MOC name is provided and not "(Skip - no MOC)", append to MOC
  if moc_name and moc_name ~= "" and moc_name ~= "(Skip - no MOC)" then
    vim.wait(200, function() end) -- Wait for template to apply

    -- Use pure Lua implementation
    vim.schedule(function()
      local success = M.append_to_moc(moc_name, note_title, "Related Projects")
      if success then
        vim.notify(string.format("✓ Note created and added to %s", moc_name), vim.log.levels.INFO)
      end
    end)
  end
end

-- Keymap
vim.api.nvim_set_keymap(
  "n",
  "<leader>oc",
  ":lua require('user_functions.obsidian_notes').select_note_type_and_create()<CR>",
  { noremap = true, silent = true, desc = "Create new Obsidian note" }
)

vim.api.nvim_create_user_command("CreateNoteWithTemplate", function(input)
  -- Split input to get template type, note title, and optional MOC name
  local args = vim.split(input.args, " ", { trimempty = true })
  if #args < 2 then
    print "Usage: CreateNoteWithTemplate <template_type> <note_title> [moc_name]"
    return
  end
  local template_type = args[1]
  local moc_name = args[#args] -- Last arg might be MOC name
  local note_title

  -- Check if last arg is a MOC name
  if moc_name:match "-MOC$" or moc_name == "(Skip - no MOC)" then
    note_title = table.concat({ select(2, unpack(args)) }, " ", 1, #args - 2)
  else
    note_title = table.concat({ select(2, unpack(args)) }, " ")
    moc_name = nil
  end

  M.create_note_with_template(template_type, note_title, moc_name)
end, { nargs = "+" })

return M
