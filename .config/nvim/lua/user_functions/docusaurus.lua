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
        if name == "_partials" or name == "_fragments" or name == "_code" then
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
local function get_repository_path(file_path)
  local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
  return file_path:sub(#git_root + 2) -- +2 to remove leading slash
end
-- Function specifically for code block imports
function M.select_code_block()
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
    prompt_title = "Select Code Block",
    search_dirs = partials_dirs,
    path_display = { shorten = 3 },
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", function()
        local selection = require("telescope.actions.state").get_selected_entry()
        local partial_path = selection.path

        -- Close Telescope before prompting
        require("telescope.actions").close(prompt_bufnr)

        -- Generate default component name based on the file name
        local partial_name = M.to_camel_case(partial_path)

        -- Prompt for the component name with default value
        partial_name = vim.fn.input("Name the code block: ", partial_name)

        -- Switch back to the original window and buffer
        vim.api.nvim_set_current_win(current_win)
        vim.api.nvim_set_current_buf(current_bufnr)

        -- Insert code block with raw loader
        M.insert_partial_in_buffer(current_bufnr, partial_name, partial_path, true)
      end)
      return true
    end,
  }
end

-- Function to convert a string to CamelCase using only the file name
function M.to_camel_case(str)
  -- Extract the file name without extension
  local file_name = vim.fn.fnamemodify(str, ":t:r")

  local words = {}
  -- Split the file name by hyphens and underscores
  for word in string.gmatch(file_name, "[^%-%_]+") do
    word = word:gsub("^%l", string.upper)
    table.insert(words, word)
  end
  return table.concat(words)
end

-- Function to convert file name to readable text
function M.to_readable_text(str)
  -- Extract the file name without extension
  local file_name = vim.fn.fnamemodify(str, ":t:r")
  -- Replace hyphens and underscores with spaces
  return file_name:gsub("[%-_]", " ")
end
-- Function to get relative path between two absolute paths
local function get_relative_path(from_dir, to_path)
  local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")

  -- Print paths for debugging
  print("From dir:", from_dir)
  print("To path:", to_path)
  print("Git root:", git_root)

  local from_rel = from_dir:sub(#git_root + 2)
  local to_rel = to_path:sub(#git_root + 2)

  print("From relative:", from_rel)
  print("To relative:", to_rel)

  local from_parts = vim.split(from_rel, "/")
  local to_parts = vim.split(to_rel, "/")

  local i = 1
  while i <= #from_parts and i <= #to_parts and from_parts[i] == to_parts[i] do
    i = i + 1
  end

  local result = {}
  for _ = i, #from_parts do
    table.insert(result, "..")
  end

  for j = i, #to_parts do
    table.insert(result, to_parts[j])
  end

  local final_path = table.concat(result, "/")
  print("Final path:", final_path)
  return final_path
end
-- Function to get absolute URL path
local function get_absolute_url_path(file_path)
  -- Get git repository root
  local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")

  -- Remove git root from path and file extension
  local url_path = file_path:sub(#git_root + 2) -- +2 to remove leading slash
  url_path = vim.fn.fnamemodify(url_path, ":r")

  -- Ensure forward slashes
  url_path = url_path:gsub("\\", "/")

  -- Add leading slash
  url_path = "/" .. url_path

  return url_path
end

function M.insert_partial_in_buffer(bufnr, partial_name, partial_path, is_raw_loader)
  -- Switch to the buffer
  vim.api.nvim_set_current_buf(bufnr)

  -- Get the cursor position in the correct window
  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor_position[1]

  local insert_text
  if is_raw_loader then
    -- For raw loader, create CodeBlock component with a placeholder for language
    insert_text = string.format(
      '<CodeBlock language="yaml" title="%s">{%s}</CodeBlock>',
      M.to_readable_text(partial_path),
      partial_name
    )
  else
    -- For regular partials
    insert_text = string.format("<%s />", partial_name)
  end

  -- Insert the component at the cursor position
  vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line - 1, false, { insert_text })

  -- If this is a code block, position cursor between the quotes of language
  if is_raw_loader then
    -- Find the start of 'language="' in the line
    local line_content = vim.api.nvim_buf_get_lines(bufnr, current_line - 1, current_line, false)[1]
    local lang_start = string.find(line_content, 'language="')
    if lang_start then
      -- Position cursor between the quotes (add 10 to get between the quotes)
      vim.api.nvim_win_set_cursor(0, { current_line, lang_start + 10 })
    end
  end

  -- Rest of the function (imports handling) remains the same
  local current_file_path = vim.api.nvim_buf_get_name(bufnr)
  local current_file_dir = vim.fn.fnamemodify(current_file_path, ":h")
  -- ... rest of your existing code ...

  local import_statement
  if is_raw_loader then
    -- For raw loader, use absolute path from repository root
    local repo_path = get_repository_path(partial_path)
    import_statement = string.format("import %s from '!!raw-loader!@site/%s';", partial_name, repo_path)
  else
    -- For regular partials, use relative path
    local relative_path = get_relative_path(current_file_dir, partial_path)
    import_statement = string.format("import %s from '%s';", partial_name, relative_path)
  end

  -- Get the buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local insert_pos = 1
  local found_front_matter_start = false
  local found_front_matter_end = false
  local found_import = false
  local has_codeblock_import = false

  -- Find the front matter and import section from the top
  for i, line in ipairs(lines) do
    if not found_front_matter_start then
      if line:match "^---$" then
        found_front_matter_start = true
      end
    elseif not found_front_matter_end then
      if line:match "^---$" then
        found_front_matter_end = true
        insert_pos = i + 1
      end
    elseif line:match "^import" then
      found_import = true
      insert_pos = i + 1
      if line:match "^import CodeBlock from '@theme/CodeBlock'" then
        has_codeblock_import = true
      end
    end
  end

  -- Insert imports
  local imports = {}
  if is_raw_loader and not has_codeblock_import then
    table.insert(imports, "import CodeBlock from '@theme/CodeBlock'")
  end
  table.insert(imports, import_statement)

  if #imports > 0 then
    table.insert(imports, "") -- Add empty line after imports
    vim.api.nvim_buf_set_lines(bufnr, insert_pos - 1, insert_pos - 1, false, imports)
  end
end

-- Function to insert URL reference at cursor
local function insert_url_reference(bufnr, target_path)
  -- Get URL path
  local url_path = get_absolute_url_path(target_path)

  -- Get the cursor position
  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor_position[1]

  -- Generate default link text from file name
  local default_text = M.to_readable_text(target_path)

  -- Prompt for link text with default value
  local link_text = vim.fn.input("Enter link text: ", default_text)
  if link_text == "" then
    link_text = default_text
  end

  local markdown_link = string.format("[%s](%s)", link_text, url_path)

  -- Insert the markdown link at cursor position
  local line_content = vim.api.nvim_buf_get_lines(bufnr, current_line - 1, current_line, false)[1]
  local cursor_col = cursor_position[2]

  -- Split the line at cursor position and insert the link
  local new_line = string.sub(line_content, 1, cursor_col) .. markdown_link .. string.sub(line_content, cursor_col + 1)
  vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line, false, { new_line })
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
    search_dirs = partials_dirs,
    path_display = { shorten = 3 },
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", function()
        local selection = require("telescope.actions.state").get_selected_entry()
        local partial_path = selection.path

        -- Generate default component name based on the file name
        local partial_name = M.to_camel_case(partial_path)

        -- Prompt for the component name with default value
        partial_name = vim.fn.input("Name the partial: ", partial_name)

        -- Close Telescope before switching back
        require("telescope.actions").close(prompt_bufnr)

        -- Switch back to the original window and buffer
        vim.api.nvim_set_current_win(current_win)
        vim.api.nvim_set_current_buf(current_bufnr)

        -- Insert partial (always as regular import)
        M.insert_partial_in_buffer(current_bufnr, partial_name, partial_path, false)
      end)
      return true
    end,
  }
end

function M.insert_url_reference()
  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()

  local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("%s+", "")
  if git_root == "" then
    print "Not inside a git repository."
    return
  end

  -- Change to git root directory
  vim.fn.chdir(git_root)

  require("telescope.builtin").find_files {
    prompt_title = "Select MDX File to Reference",
    search_dirs = { "." }, -- Search from current (git root) directory
    find_command = { "find", ".", "-type", "f", "-name", "*.mdx", "!", "-path", "*/_*/*" },
    path_display = { truncate = 3 },
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", function()
        local selection = require("telescope.actions.state").get_selected_entry()
        local file_path = selection.path
        require("telescope.actions").close(prompt_bufnr)
        vim.api.nvim_set_current_win(current_win)
        vim.api.nvim_set_current_buf(current_bufnr)
        insert_url_reference(current_bufnr, file_path)
      end)
      return true
    end,
  }

  -- Change back to original directory
  vim.fn.chdir "-"
end

-- Function to insert component in buffer
local function insert_component_in_buffer(bufnr, component_name)
  -- Switch to the buffer
  vim.api.nvim_set_current_buf(bufnr)

  -- Get the cursor position in the correct window
  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor_position[1]

  local component_insert = string.format("<%s />", component_name)

  -- Insert the component at the cursor position
  vim.api.nvim_buf_set_lines(bufnr, current_line - 1, current_line - 1, false, { component_insert })
  print("Component inserted: " .. component_insert .. " at line " .. current_line)

  -- Add import statement
  local import_statement = string.format("import %s from '@site/src/components/%s';", component_name, component_name)

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
      end
    elseif not found_front_matter_end then
      if line:match "^---$" then
        found_front_matter_end = true
        insert_pos = i + 1
      end
    elseif line:match "^import" then
      found_import = true
      insert_pos = i + 1
    end
  end

  -- Insert the import statement
  vim.api.nvim_buf_set_lines(bufnr, insert_pos - 1, insert_pos - 1, false, { "", import_statement, "" })
end

function M.select_component()
  -- Capture the current buffer and window
  local current_bufnr = vim.api.nvim_get_current_buf()
  local current_win = vim.api.nvim_get_current_win()

  -- Set components directory path
  local components_dir = vim.fn.expand "~/loft/vcluster-docs/src/components"

  if vim.fn.isdirectory(components_dir) ~= 1 then
    print("Components directory not found at: " .. components_dir)
    return
  end

  -- Get list of component directories
  local components = vim.fn.readdir(components_dir)
  local component_entries = {}

  -- Create entries for telescope
  for _, name in ipairs(components) do
    local full_path = components_dir .. "/" .. name
    if vim.fn.isdirectory(full_path) == 1 then
      table.insert(component_entries, {
        value = name,
        display = name,
        ordinal = name:lower(),
      })
    end
  end

  -- Create picker using Telescope
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  -- Function to get component file content
  local function get_component_content(name)
    local base_path = components_dir .. "/" .. name
    local possible_files = {
      "/index.js",
      "/index.jsx",
      "/" .. name .. ".js",
      "/" .. name .. ".jsx",
    }

    for _, file in ipairs(possible_files) do
      local full_path = base_path .. file
      if vim.fn.filereadable(full_path) == 1 then
        local content = vim.fn.readfile(full_path)
        return table.concat(content, "\n")
      end
    end
    return "No component file found"
  end

  pickers
    .new({}, {
      prompt_title = "Select Component",
      finder = finders.new_table {
        results = component_entries,
        entry_maker = function(entry)
          return {
            value = entry.value,
            display = entry.display,
            ordinal = entry.ordinal,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = require("telescope.previewers").new_buffer_previewer {
        title = "Component Content",
        define_preview = function(self, entry, status)
          local content = get_component_content(entry.value)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(content, "\n"))

          -- Set filetype for syntax highlighting
          if content:match "%.jsx?$" then
            vim.bo[self.state.bufnr].filetype = "javascriptreact"
          else
            vim.bo[self.state.bufnr].filetype = "javascript"
          end
        end,
      },
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          -- Switch back to the original window and buffer
          vim.api.nvim_set_current_win(current_win)
          vim.api.nvim_set_current_buf(current_bufnr)

          -- Insert component
          insert_component_in_buffer(current_bufnr, selection.value)
        end)
        return true
      end,
    })
    :find()
end

-- Add key bindings
vim.api.nvim_set_keymap(
  "n",
  "<leader>ic",
  "",
  { noremap = true, silent = true, callback = M.select_component, desc = "Insert Docusaurus Component" }
)
vim.api.nvim_set_keymap(
  "n",
  "<leader>ip",
  "",
  { noremap = true, silent = true, callback = M.select_partial, desc = "Insert Docusaurus Partial" }
)
vim.api.nvim_set_keymap(
  "n",
  "<leader>ib",
  "",
  { noremap = true, silent = true, callback = M.select_code_block, desc = "Insert Docusaurus CodeBlock" }
)
vim.api.nvim_set_keymap(
  "n",
  "<leader>iu",
  "",
  { noremap = true, silent = true, callback = M.insert_url_reference, desc = "Insert Docusaurus URL Reference" }
)

return M
