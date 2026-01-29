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
  -- Auto-discover MOCs from _mocs directory
  local vault_path = vim.fn.expand "~" .. "/dev/obsidian/decoder"
  local moc_path = vault_path .. "/Notes/_mocs"
  local moc_files = vim.fn.globpath(moc_path, "*.md", false, true)

  local mocs = {}
  for _, filepath in ipairs(moc_files) do
    local moc_name = vim.fn.fnamemodify(filepath, ":t:r")
    table.insert(mocs, moc_name)
  end

  -- Sort alphabetically
  table.sort(mocs)

  -- Add skip option at the end
  table.insert(mocs, "(Skip - no MOC)")

  vim.ui.select(mocs, { prompt = "Add to which MOC?" }, function(moc_choice)
    if not moc_choice then
      return
    end

    vim.cmd("CreateNoteWithTemplate " .. note_type .. " " .. note_title .. " " .. (moc_choice or ""))
  end)
end

-- Find MOC section boundaries in index
local function find_moc_section_end(lines)
  for i, line in ipairs(lines) do
    if line:match "^## " and not line:match "Maps of Content" then
      return i - 1
    end
  end
  return -1
end

-- Find last MOC entry line
local function find_last_moc_line(lines, section_end)
  for i = section_end, 1, -1 do
    if lines[i]:match "^%- %[%[" then
      return i
    end
  end
  return -1
end

-- Insert MOC entry into lines
local function insert_moc_entry(lines, last_moc_line, moc_name)
  local new_entry = "- [[" .. moc_name .. "]] - [Add description]"
  local new_lines = {}
  for i, line in ipairs(lines) do
    table.insert(new_lines, line)
    if i == last_moc_line then
      table.insert(new_lines, new_entry)
    end
  end
  return new_lines
end

-- Add MOC to 00-INDEX.md
local function add_moc_to_index(moc_name)
  local vault_path = vim.fn.expand "~" .. "/dev/obsidian"
  local index_file = vault_path .. "/decoder/Notes/00-INDEX.md"

  if vim.fn.filereadable(index_file) ~= 1 then
    return false
  end

  -- Read index file
  local lines = {}
  for line in io.lines(index_file) do
    table.insert(lines, line)
  end

  local section_end = find_moc_section_end(lines)
  if section_end == -1 then
    return false
  end

  local last_moc_line = find_last_moc_line(lines, section_end)
  if last_moc_line == -1 then
    return false
  end

  local new_lines = insert_moc_entry(lines, last_moc_line, moc_name)

  -- Write file
  local file = io.open(index_file, "w")
  if not file then
    return false
  end

  for _, line in ipairs(new_lines) do
    file:write(line .. "\n")
  end
  file:close()
  return true
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

  -- Add to 00-INDEX.md
  vim.schedule(function()
    if add_moc_to_index(moc_name) then
      vim.notify("✓ Created " .. moc_name .. " and added to 00-INDEX.md!", vim.log.levels.INFO)
    else
      vim.notify("✓ Created " .. moc_name .. " - Please add to 00-INDEX.md manually", vim.log.levels.WARN)
    end
  end)
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

-- Read all MOC files content
local function read_moc_content(moc_path)
  local moc_content = ""
  local moc_files = vim.fn.globpath(moc_path, "*.md", false, true)
  for _, moc_file in ipairs(moc_files) do
    local file = io.open(moc_file, "r")
    if file then
      moc_content = moc_content .. file:read "*all"
      file:close()
    end
  end
  return moc_content
end

-- Check if note is orphaned (has no incoming links)
local function is_note_orphaned(filepath, moc_content, all_files)
  local note_name = vim.fn.fnamemodify(filepath, ":t:r")

  -- Escape special pattern characters in note name
  local escaped_name = note_name:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%1")

  -- Check if note is referenced in MOCs
  local in_moc = moc_content:match("%[%[" .. escaped_name) ~= nil

  -- Check if note is referenced in OTHER notes (excluding itself)
  local has_incoming_links = false
  for _, other_filepath in ipairs(all_files) do
    -- Skip the current file itself
    if other_filepath ~= filepath then
      local file = io.open(other_filepath, "r")
      if file then
        local content = file:read "*all"
        file:close()
        if content:match("%[%[" .. escaped_name) then
          has_incoming_links = true
          break
        end
      end
    end
  end

  return not in_moc and not has_incoming_links
end

-- Check if filename is a daily note (date pattern)
local function is_daily_note(filename)
  -- Match YYYY-MM-DD or YYYY-MM-DD-* patterns
  return filename:match "^%d%d%d%d%-%d%d%-%d%d" ~= nil
end

-- Collect orphaned notes by type
local function collect_orphans(vault_path, moc_content)
  local all_files = vim.fn.globpath(vault_path, "**/*.md", false, true)
  local orphans = {}
  local total = 0
  local orphan_count = 0

  for _, filepath in ipairs(all_files) do
    local filename = vim.fn.fnamemodify(filepath, ":t:r")

    -- Skip MOCs, INDEX, and daily notes
    if not filepath:match "/_mocs/" and not filepath:match "00%-INDEX" and not is_daily_note(filename) then
      total = total + 1
      -- Pass all_files so the function can check other files for incoming links
      if is_note_orphaned(filepath, moc_content, all_files) then
        orphan_count = orphan_count + 1
        local note_type = vim.fn.fnamemodify(filepath, ":h:t")

        -- Dynamically create category if it doesn't exist
        if not orphans[note_type] then
          orphans[note_type] = {}
        end
        table.insert(orphans[note_type], filename)
      end
    end
  end

  return orphans, total, orphan_count
end

-- Generate report lines
local function generate_report_lines(orphans, total, orphan_count)
  local report = {
    "=== OBSIDIAN ORPHAN REPORT ===",
    "Generated: " .. os.date "%Y-%m-%d %H:%M",
    "",
    "Total notes: " .. total,
    "Orphaned notes: " .. orphan_count,
    "Orphan percentage: " .. string.format("%.1f%%", (orphan_count / total) * 100),
    "",
    "=== ORPHANED NOTES (no links + not in MOCs) ===",
    "",
  }

  for note_type, notes in pairs(orphans) do
    if #notes > 0 then
      table.insert(report, "## " .. note_type)
      for _, note_name in ipairs(notes) do
        table.insert(report, "  - " .. note_name)
      end
      table.insert(report, "")
    end
  end

  table.insert(report, "=== RECOMMENDATIONS ===")
  if orphan_count > 30 then
    table.insert(report, "⚠ High orphan count - prioritize linking these notes to MOCs")
  elseif orphan_count > 10 then
    table.insert(report, "⚡ Moderate orphan count - continue linking work")
  else
    table.insert(report, "✓ Low orphan count - vault is well-organized!")
  end

  return report
end

-- Show orphaned notes report
function M.show_orphan_report()
  local vault_path = vim.fn.expand "~" .. "/dev/obsidian/decoder/Notes"
  local moc_path = vim.fn.expand "~" .. "/dev/obsidian/decoder/Notes/_mocs"

  local moc_content = read_moc_content(moc_path)
  local orphans, total, orphan_count = collect_orphans(vault_path, moc_content)
  local report = generate_report_lines(orphans, total, orphan_count)

  -- Create report buffer
  vim.cmd "new"
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_name(buf, "Orphaned Notes Report")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, report)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

-- Keymap
vim.api.nvim_set_keymap(
  "n",
  "<leader>oc",
  ":lua require('user_functions.obsidian_notes').select_note_type_and_create()<CR>",
  { noremap = true, silent = true, desc = "Create new Obsidian note" }
)

vim.api.nvim_set_keymap(
  "n",
  "<leader>oo",
  ":lua require('user_functions.obsidian_notes').show_orphan_report()<CR>",
  { noremap = true, silent = true, desc = "Show orphaned notes report" }
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
    note_title = table.concat({ select(2, table.unpack(args)) }, " ", 1, #args - 2)
  else
    note_title = table.concat({ select(2, table.unpack(args)) }, " ")
    moc_name = nil
  end

  M.create_note_with_template(template_type, note_title, moc_name)
end, { nargs = "+" })

return M
