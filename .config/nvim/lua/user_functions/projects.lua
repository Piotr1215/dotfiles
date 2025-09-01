-- ~/.config/nvim/lua/user_functions/projects.lua
local M = {}

local function get_projects_file_path()
	return vim.fn.expand("~/dev/dotfiles/projects.txt")
end

local function load_existing_projects()
	local file_path = get_projects_file_path()
	local projects = {}
	local file = io.open(file_path, "r")

	if file then
		for line in file:lines() do
			local trimmed = line:match("^%s*(.-)%s*$")
			if trimmed ~= "" then
				projects[trimmed] = true
			end
		end
		file:close()
	end

	return projects
end

local function add_project_to_file(project_name)
	local file_path = get_projects_file_path()
	local file = io.open(file_path, "a")

	if file then
		file:write(project_name .. "\n")
		file:close()
		return true
	end

	return false
end

function M.add_project_from_line(current_line)
	local project_pattern = "PROJECT:%s*(%S+)"
	local project_name = current_line:match(project_pattern)

	if not project_name then
		require("notify")("No project name found on the line.", "error")
		return false
	end

	local existing_projects = load_existing_projects()

	if existing_projects[project_name] then
		require("notify")("Project already exists: " .. project_name, "info")
		return false
	else
		if add_project_to_file(project_name) then
			require("notify")("Project added: " .. project_name, "info")
			return true
		else
			require("notify")("Failed to open the file.", "error")
			return false
		end
	end
end

-- Smart autocommand to automatically detect and add projects on buffer save
local function setup_smart_project_detection()
	local group = vim.api.nvim_create_augroup("SmartProjectDetection", { clear = true })

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = "*",
		callback = function()
			local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			local project_pattern = "PROJECT:%s*(%S+)"
			local existing_projects = load_existing_projects()
			local added_projects = {}

			for _, line in ipairs(lines) do
				local project_name = line:match(project_pattern)
				if project_name and not existing_projects[project_name] and not added_projects[project_name] then
					if add_project_to_file(project_name) then
						added_projects[project_name] = true
						existing_projects[project_name] = true -- Update local cache
					end
				end
			end

			-- Show notification for all newly added projects
			local count = 0
			for project_name, _ in pairs(added_projects) do
				count = count + 1
			end

			if count > 0 then
				local project_names = {}
				for project_name, _ in pairs(added_projects) do
					table.insert(project_names, project_name)
				end
				require("notify")(
					"Auto-added " .. count .. " project(s): " .. table.concat(project_names, ", "),
					"info"
				)
			end
		end,
	})
end

-- Initialize smart detection
setup_smart_project_detection()

-- Create a keymap to manually call the add_project_from_line function
vim.api.nvim_set_keymap(
	"i", -- Insert mode
	"<C-x>",
	[[<Cmd>lua require('user_functions.projects').add_project_from_line(vim.fn.getline('.'))<CR>]], -- Passes current line to the function
	{ noremap = true, silent = false }
)

-- Load telescope projects functionality
require("user_functions.telescope_projects")

return M
