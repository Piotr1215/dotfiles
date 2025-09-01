-- ~/.config/nvim/lua/user_functions/bookmarks.lua
local M = {}

-- Add a path to bookmarks
function M.add_path_to_bookmarks(path)
	-- Validate the path exists
	if path == "" then
		vim.notify("No path provided", vim.log.levels.ERROR)
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
		f:write("#!/bin/bash\n")
		f:write("set -eo pipefail\n\n")
		f:write(string.format('BOOKMARKS_FILE="$HOME/dev/dotfiles/scripts/__bookmarks.conf"\n\n'))
		f:write(string.format('DESCRIPTION="%s"\n', description:gsub('"', '\\"')))
		f:write(string.format('FILE_PATH="%s"\n\n', path:gsub('"', '\\"')))

		-- Check if the bookmark already exists
		f:write('if grep -q "^.*;$FILE_PATH$" "$BOOKMARKS_FILE"; then\n')
		f:write("  # Remove existing entry\n")
		f:write('  sed -i "\\#^.*;$FILE_PATH\\$#d" "$BOOKMARKS_FILE"\n')
		f:write("fi\n\n")

		-- Add the new bookmark
		f:write("# Add bookmark\n")
		f:write('echo "$DESCRIPTION;$FILE_PATH" >> "$BOOKMARKS_FILE"\n\n')

		-- Sort the bookmarks file
		f:write("# Sort the bookmarks file\n")
		f:write('LC_ALL=C sort -f "$BOOKMARKS_FILE" -o "$BOOKMARKS_FILE"\n')

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

-- Add the current file to bookmarks
function M.add_current_file_to_bookmarks()
	-- Get the current file's full path
	local file_path = vim.fn.expand("%:p")

	-- Validate the file exists
	if file_path == "" then
		vim.notify("No file is open", vim.log.levels.ERROR)
		return
	end

	M.add_path_to_bookmarks(file_path)
end

-- Add the current file's folder to bookmarks
function M.add_current_folder_to_bookmarks()
	-- Get the current file's directory
	local folder_path = vim.fn.expand("%:p:h")

	-- Validate the folder exists
	if folder_path == "" then
		vim.notify("No file is open", vim.log.levels.ERROR)
		return
	end

	M.add_path_to_bookmarks(folder_path)
end

-- Function to delete a bookmark
function M.delete_bookmark()
	-- Get the bookmarks file path
	local bookmarks_file = vim.fn.expand("~/dev/dotfiles/scripts/__bookmarks.conf")

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
		local desc, path = line:match("^(.-);(.+)$")
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
	local bookmarks_file = vim.fn.expand("~/dev/dotfiles/scripts/__bookmarks.conf")

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
		local desc, path = line:match("^(.-);(.+)$")
		if desc and path then
			table.insert(bookmarks, {
				description = desc,
				path = path,
				display = desc .. " → " .. path,
			})
		end
	end

	-- Use Telescope to show and select a bookmark
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	pickers
		.new({}, {
			prompt_title = "Bookmarks",
			finder = finders.new_table({
				results = bookmarks,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.description .. " " .. entry.path,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					local path = selection.value.path

					-- Expand path if it starts with ~
					if path:sub(1, 1) == "~" then
						path = vim.fn.expand(path)
					end

					-- Check if it's a file or directory
					if vim.fn.isdirectory(path) == 1 then
						-- Open directory in current buffer using a file explorer
						-- Check if mini.files is available (which it is based on plugins-setup.lua)
						local status, mini_files = pcall(require, "mini.files")
						if status then
							mini_files.open(path)
						else
							-- Fallback to netrw if mini.files isn't available
							vim.cmd("edit " .. vim.fn.fnameescape(path))
						end
					else
						-- Edit files directly
						vim.cmd("edit " .. vim.fn.fnameescape(path))
					end
				end)
				return true
			end,
		})
		:find()
end

-- Function to open the bookmarks file directly
function M.edit_bookmarks_file()
	vim.cmd("edit ~/dev/dotfiles/scripts/__bookmarks.conf")
end

-- Add keybindings
vim.api.nvim_set_keymap(
	"n",
	"<leader>ba",
	"<cmd>lua require('user_functions.bookmarks').add_current_file_to_bookmarks()<CR>",
	{ noremap = true, silent = true, desc = "Add current file to bookmarks" }
)

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
