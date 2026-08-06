-- ~/.config/nvim/lua/user_functions/bookmarks.lua
local M = {}

local uv = vim.uv or vim.loop

local function bookmarks_file_path()
  return vim.env.BOOKMARKS_FILE or vim.fn.expand "~/dev/dotfiles/scripts/__bookmarks.conf"
end

local function parse_bookmark_target(target)
  local path, line_number = target:match "^(.*);(%d+)$"
  if path then
    return path, tonumber(line_number)
  end
  return target, nil
end

M.parse_bookmark_target = parse_bookmark_target

-- The path under the cursor. A mini.files buffer is named `minifiles://<id>/...`,
-- which is a buffer URI and not a path on disk, so expand() there yields something
-- no shell can open. Ask mini.files for the real entry instead.
local function current_fs_entry()
  if vim.api.nvim_buf_get_name(0):match "^minifiles://" then
    local ok, mini_files = pcall(require, "mini.files")
    if not ok then
      return nil
    end
    local entry = mini_files.get_fs_entry()
    if not entry then
      return nil
    end
    return entry.path, entry.fs_type
  end

  local path = vim.fn.expand "%:p"
  if path == "" then
    return nil
  end
  return path, "file"
end

-- Add a path to bookmarks
function M.add_path_to_bookmarks(path, line_number)
  -- Validate the path exists
  if path == "" then
    vim.notify("No path provided", vim.log.levels.ERROR)
    return
  end

  -- A bookmark that does not resolve is worse than no bookmark: it sits in the
  -- list looking valid until the day you pick it.
  if not uv.fs_stat(path) then
    vim.notify("Path does not exist: " .. path, vim.log.levels.ERROR)
    return
  end

  -- Prompt for a description
  vim.ui.input({ prompt = "Description for bookmark: " }, function(description)
    if not description or description == "" then
      vim.notify("Bookmark creation cancelled - no description provided", vim.log.levels.WARN)
      return
    end

    -- Create a temporary script to ensure proper handling of special characters
    local temp_script = os.tmpname()
    local f = io.open(temp_script, "w")
    if not f then
      vim.notify("Failed to create temporary script", vim.log.levels.ERROR)
      return
    end

    -- Write commands to the temp script
    f:write "#!/bin/bash\n"
    f:write "set -eo pipefail\n\n"
    f:write(string.format("BOOKMARKS_FILE=%s\n\n", vim.fn.shellescape(bookmarks_file_path())))
    f:write(string.format('DESCRIPTION="%s"\n', description:gsub('"', '\\"')))
    f:write(string.format('FILE_PATH="%s"\n\n', path:gsub('"', '\\"')))
    f:write(string.format('LINE_NUMBER="%s"\n', line_number or ""))
    f:write 'BOOKMARK_TARGET="$FILE_PATH"\n'
    f:write '[ -z "$LINE_NUMBER" ] || BOOKMARK_TARGET="$BOOKMARK_TARGET;$LINE_NUMBER"\n\n'

    -- Replace only the same target. A file bookmark and several line bookmarks
    -- in that file are distinct entries.
    f:write ': > "$BOOKMARKS_FILE.tmp"\n'
    f:write "while IFS= read -r BOOKMARK_LINE; do\n"
    f:write '  [ "${BOOKMARK_LINE#*;}" = "$BOOKMARK_TARGET" ] || printf "%s\\n" "$BOOKMARK_LINE" >> "$BOOKMARKS_FILE.tmp"\n'
    f:write 'done < "$BOOKMARKS_FILE"\n'
    f:write 'mv "$BOOKMARKS_FILE.tmp" "$BOOKMARKS_FILE"\n\n'

    -- Add the new bookmark
    f:write "# Add bookmark\n"
    f:write 'echo "$DESCRIPTION;$BOOKMARK_TARGET" >> "$BOOKMARKS_FILE"\n\n'

    -- Sort the bookmarks file
    f:write "# Sort the bookmarks file\n"
    f:write 'LC_ALL=C sort -f "$BOOKMARKS_FILE" -o "$BOOKMARKS_FILE"\n'

    f:close()

    -- Make the script executable
    vim.fn.system("chmod +x " .. temp_script)

    -- Execute the temporary script
    local result = vim.fn.system(temp_script)
    local success = vim.v.shell_error == 0

    -- Clean up
    vim.fn.system("rm " .. temp_script)

    if success then
      vim.notify("Bookmark added: " .. description, vim.log.levels.INFO)
    else
      vim.notify("Failed to add bookmark:\n" .. result, vim.log.levels.ERROR)
    end
  end)
end

-- Add the entry under the cursor to bookmarks
function M.add_current_file_to_bookmarks()
  local path = current_fs_entry()

  if not path then
    vim.notify("No file is open", vim.log.levels.ERROR)
    return
  end

  M.add_path_to_bookmarks(path)
end

-- Add the current visual selection as a bookmark to its first line.
function M.add_current_selection_to_bookmarks()
  local path, fs_type = current_fs_entry()

  if not path or fs_type == "directory" then
    vim.notify("No file is open", vim.log.levels.ERROR)
    return
  end

  local first_line = math.min(vim.fn.line "'<", vim.fn.line "'>")
  M.add_path_to_bookmarks(path, first_line)
end

-- Add the folder holding the entry under the cursor. In mini.files a directory
-- under the cursor bookmarks itself rather than its parent, which is what you mean
-- when you are standing in the tree looking at it.
function M.add_current_folder_to_bookmarks()
  local path, fs_type = current_fs_entry()

  if not path then
    vim.notify("No file is open", vim.log.levels.ERROR)
    return
  end

  if fs_type ~= "directory" then
    path = vim.fs.dirname(path)
  end

  M.add_path_to_bookmarks(path)
end

-- Function to delete a bookmark
function M.delete_bookmark()
  -- Get the bookmarks file path
  local bookmarks_file = bookmarks_file_path()

  -- Read the bookmarks file
  local lines = {}
  local f = io.open(bookmarks_file, "r")
  if not f then
    vim.notify("Failed to open bookmarks file", vim.log.levels.ERROR)
    return
  end

  for line in f:lines() do
    if line ~= "" then -- Skip empty lines
      table.insert(lines, line)
    end
  end
  f:close()

  if #lines == 0 then
    vim.notify("No bookmarks to delete", vim.log.levels.WARN)
    return
  end

  -- Extract descriptions for the selection prompt
  local descriptions = {}
  local path_map = {}
  for i, line in ipairs(lines) do
    local desc, path = line:match "^(.-);(.+)$"
    if desc and path then
      descriptions[i] = desc .. " → " .. path
      path_map[i] = { desc = desc, path = path }
    else
      descriptions[i] = line
      path_map[i] = { desc = line, path = "" }
    end
  end

  -- Show the selection dialog using vim.ui.select
  vim.ui.select(descriptions, {
    prompt = "Select bookmark to delete:",
  }, function(choice, idx)
    if not choice then
      return
    end

    -- Simple approach: Create new content and write it
    local new_content = {}
    for i, line in ipairs(lines) do
      if i ~= idx then
        table.insert(new_content, line)
      end
    end

    -- Write the new content directly
    local script = io.open(bookmarks_file, "w")
    if not script then
      vim.notify("Failed to open bookmarks file for writing", vim.log.levels.ERROR)
      return
    end

    for _, line in ipairs(new_content) do
      script:write(line .. "\n")
    end

    script:close()

    vim.notify("Bookmark deleted: " .. path_map[idx].desc, vim.log.levels.INFO)
  end)
end

-- Function to list bookmarks and open the selected one
function M.list_bookmarks()
  -- Get the bookmarks file path
  local bookmarks_file = bookmarks_file_path()

  -- Read the bookmarks file
  local lines = {}
  local f = io.open(bookmarks_file, "r")
  if not f then
    vim.notify("Failed to open bookmarks file", vim.log.levels.ERROR)
    return
  end

  for line in f:lines() do
    if line ~= "" then -- Skip empty lines
      table.insert(lines, line)
    end
  end
  f:close()

  if #lines == 0 then
    vim.notify("No bookmarks available", vim.log.levels.WARN)
    return
  end

  -- Parse bookmarks into a format suitable for Telescope
  local bookmarks = {}
  for _, line in ipairs(lines) do
    local desc, target = line:match "^(.-);(.+)$"
    if desc and target then
      local path, line_number = parse_bookmark_target(target)
      local location = path .. (line_number and ":" .. line_number or "")
      table.insert(bookmarks, {
        description = desc,
        path = path,
        line = line_number,
        display = desc .. " → " .. location,
      })
    end
  end

  -- Use Telescope to show and select a bookmark
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  pickers
    .new({}, {
      prompt_title = "Bookmarks",
      finder = finders.new_table {
        results = bookmarks,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.description .. " " .. entry.path,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          local path = selection.value.path
          local line_number = selection.value.line

          M.open_bookmark(path, line_number)
        end)
        return true
      end,
    })
    :find()
end

function M.open_bookmark(path, line_number)
  if path:sub(1, 1) == "~" then
    path = vim.fn.expand(path)
  end

  if vim.fn.isdirectory(path) == 1 then
    local status, mini_files = pcall(require, "mini.files")
    if status then
      mini_files.open(path)
    else
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    end
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))
  if line_number then
    local last_line = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { math.min(line_number, last_line), 0 })
    vim.cmd "normal! zz"
  end
end

-- Function to open the bookmarks file directly
function M.edit_bookmarks_file()
  vim.cmd "edit ~/dev/dotfiles/scripts/__bookmarks.conf"
end

-- Add keybindings
vim.api.nvim_set_keymap(
  "n",
  "<leader>ba",
  "<cmd>lua require('user_functions.bookmarks').add_current_file_to_bookmarks()<CR>",
  { noremap = true, silent = true, desc = "Add current file to bookmarks" }
)

vim.keymap.set("x", "<leader>ba", M.add_current_selection_to_bookmarks, {
  silent = true,
  desc = "Add selected line to bookmarks",
})

vim.api.nvim_set_keymap(
  "n",
  "<leader>bA",
  "<cmd>lua require('user_functions.bookmarks').add_current_folder_to_bookmarks()<CR>",
  { noremap = true, silent = true, desc = "Add current folder to bookmarks" }
)

vim.api.nvim_set_keymap(
  "n",
  "<leader>bd",
  "<cmd>lua require('user_functions.bookmarks').delete_bookmark()<CR>",
  { noremap = true, silent = true, desc = "Delete a bookmark" }
)

vim.api.nvim_set_keymap(
  "n",
  "<leader>bl",
  "<cmd>lua require('user_functions.bookmarks').list_bookmarks()<CR>",
  { noremap = true, silent = true, desc = "List bookmarks" }
)

vim.api.nvim_set_keymap(
  "n",
  "<leader>be",
  "<cmd>lua require('user_functions.bookmarks').edit_bookmarks_file()<CR>",
  { noremap = true, silent = true, desc = "Edit bookmarks file" }
)

return M
