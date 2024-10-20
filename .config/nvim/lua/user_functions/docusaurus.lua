local M = {}

-- Function to recursively find all _partials directories in the repository
local function get_all_partials_dirs()
  local partials_dirs = {}

  -- Get git repository root
  local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")

  if git_root == "" then
    print "Not inside a git repository."
    return partials_dirs
  end

  local function scan_dir(dir)
    local entries = vim.fn.readdir(dir)
    for _, name in ipairs(entries) do
      local full_path = dir .. "/" .. name
      if vim.fn.isdirectory(full_path) == 1 then
        if name == "_partials" then
          table.insert(partials_dirs, full_path)
        elseif name ~= "." and name ~= ".." then
          scan_dir(full_path)
        end
      end
    end
  end

  scan_dir(git_root)
  return partials_dirs
end

-- Function to convert a string to CamelCase using only the file name
local function to_camel_case(str)
  -- Extract the file name without extension
  local file_name = vim.fn.fnamemodify(str, ":t:r") -- ':t' for tail (file name), ':r' for root (remove extension)

  local words = {}
  -- Split the file name by hyphens and underscores
  for word in string.gmatch(file_name, "[^%-%_]+") do
    word = word:gsub("^%l", string.upper)
    table.insert(words, word)
  end
  return table.concat(words)
end

-- Function to calculate the relative path between two paths
local function get_relative_path(base, target)
  local function split_path(path)
    local tbl = {}
    for part in string.gmatch(path, "[^/]+") do
      table.insert(tbl, part)
    end
    return tbl
  end

  local base_path = vim.fn.fnamemodify(base, ":p")
  local target_path = vim.fn.fnamemodify(target, ":p")

  local base_parts = split_path(base_path)
  local target_parts = split_path(target_path)

  -- Find common prefix length
  local common_length = 0
  for i = 1, math.min(#base_parts, #target_parts) do
    if base_parts[i] == target_parts[i] then
      common_length = i
    else
      break
    end
  end

  local relative_parts = {}
  for _ = common_length + 1, #base_parts do
    table.insert(relative_parts, "..")
  end
  for i = common_length + 1, #target_parts do
    table.insert(relative_parts, target_parts[i])
  end

  local relative_path = table.concat(relative_parts, "/")

  -- Ensure path uses forward slashes
  relative_path = relative_path:gsub("\\", "/")

  -- Prepend './' if the relative path doesn't start with '.' or '/'
  if not relative_path:match "^%." and not relative_path:match "^/" then
    relative_path = "./" .. relative_path
  end

  return relative_path
end

local function insert_partial_in_buffer(bufnr, partial_name, partial_path)
  -- Switch to the buffer
  vim.api.nvim_set_current_buf(bufnr)

  -- Get the cursor position in the correct window
  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor_position[1]

  local partial_insert = string.format("<%s />", partial_name)

  -- Insert the partial at the cursor position
  vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line - 1, false, { partial_insert })
  print("Partial inserted: " .. partial_insert .. " at line " .. current_line) -- Debug print

  -- Get the current file's directory
  local current_file_path = vim.api.nvim_buf_get_name(bufnr)
  local current_file_dir = vim.fn.fnamemodify(current_file_path, ":h")

  -- Calculate the relative path
  local relative_path = get_relative_path(current_file_dir, partial_path)

  local import_statement = string.format("import %s from '%s';", partial_name, relative_path)

  -- Get the buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local insert_pos = 1
  local found_front_matter_start = false
  local found_front_matter_end = false
  local found_import = false

  -- Find the front matter and import section from the top
  for i, line in ipairs(lines) do
    if not found_front_matter_start then
      if line:match "^---$" then
        found_front_matter_start = true
        print("Found front matter start at line " .. i) -- Debug print
      end
    elseif not found_front_matter_end then
      if line:match "^---$" then
        found_front_matter_end = true
        insert_pos = i + 1 -- Insert after the front matter
        print("Found front matter end at line " .. i) -- Debug print
      end
    elseif line:match "^import" then
      found_import = true
      insert_pos = i + 1 -- Insert after the last import
      print("Found import at line " .. i) -- Debug print
    else
      -- Do nothing
    end
  end

  -- Determine where to insert the import statement
  if not found_front_matter_start then
    insert_pos = 1
    print "No front matter found, inserting at top of the file" -- Debug print
  elseif not found_front_matter_end then
    print "Front matter not properly closed with '---'"
    insert_pos = insert_pos -- Keep as is, may need adjustment based on preference
  end

  -- Insert the import statement
  vim.api.nvim_buf_set_lines(bufnr, insert_pos - 1, insert_pos - 1, false, { "", import_statement, "" })
  print("Inserted import at line " .. insert_pos) -- Debug print
end

function M.select_partial()
  -- Capture the current buffer and window
  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()

  -- Get all _partials directories
  local partials_dirs = get_all_partials_dirs()

  if vim.tbl_isempty(partials_dirs) then
    print "No _partials directories found in the repository."
    return
  end

  -- Use Telescope to browse partial files
  require("telescope.builtin").find_files {
    prompt_title = "Select Partial",
    search_dirs = partials_dirs, -- Use the dynamically found directories
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", function()
        local selection = require("telescope.actions.state").get_selected_entry()
        local partial_path = selection.path

        -- Generate default component name based on the file name
        local partial_name = to_camel_case(partial_path)

        -- Prompt for the component name with default value
        partial_name = vim.fn.input("Name the partial (React component): ", partial_name)

        -- Close Telescope before switching back
        require("telescope.actions").close(prompt_bufnr)

        -- Switch back to the original window and buffer
        vim.api.nvim_set_current_win(current_win)
        vim.api.nvim_set_current_buf(current_bufnr)

        -- Insert partial and update import section
        insert_partial_in_buffer(current_bufnr, partial_name, partial_path)
      end)
      return true
    end,
  }
end

-- Add key binding for <leader>ip (insert partial)
vim.api.nvim_set_keymap("n", "<leader>ip", "", { noremap = true, silent = true, callback = M.select_partial })

return M
