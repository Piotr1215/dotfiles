-- ~/.config/nvim/lua/user_functions/presenterm.lua
local M = {}

-- Constants
local SLIDE_MARKER = "<!-- end_slide -->"
local SLIDE_PATTERN = "<!%-%- end_slide %-%->"

-- Check if buffer has frontmatter
local function get_frontmatter_end()
	local lines = vim.api.nvim_buf_get_lines(0, 0, math.min(50, vim.fn.line("$")), false)

	if lines[1] and lines[1]:match("^%-%-%-") then
		for i = 2, #lines do
			if lines[i]:match("^%-%-%-") then
				return i
			end
		end
	end

	return 0
end

-- Helper function to get all slide positions in buffer
local function get_slide_positions()
	local positions = {}
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local frontmatter_end = get_frontmatter_end()

	-- Start after frontmatter if it exists
	table.insert(positions, frontmatter_end)

	for i, line in ipairs(lines) do
		if line:match(SLIDE_PATTERN) and i > frontmatter_end then
			table.insert(positions, i)
		end
	end

	-- Add end of buffer as end of last slide
	table.insert(positions, #lines + 1)

	return positions
end

-- Get current slide number
local function get_current_slide()
	local cursor_line = vim.fn.line(".")
	local positions = get_slide_positions()

	for i = 1, #positions - 1 do
		if cursor_line <= positions[i + 1] then
			return i, positions
		end
	end

	return #positions - 1, positions
end

-- Navigate to specific slide
function M.go_to_slide(slide_num)
	local _, positions = get_current_slide()
	local total_slides = #positions - 1

	if slide_num < 1 then
		slide_num = 1
	elseif slide_num > total_slides then
		slide_num = total_slides
	end

	-- Move cursor to first line of the slide
	local target_line = positions[slide_num] + 1
	if target_line > vim.fn.line("$") then
		target_line = vim.fn.line("$")
	end

	-- Look for a header in the first few lines of the slide
	local lines = vim.api.nvim_buf_get_lines(0, target_line - 1, math.min(target_line + 10, vim.fn.line("$")), false)
	for i, line in ipairs(lines) do
		if line:match("^#+ ") or (i < #lines and lines[i + 1]:match("^=+$")) then
			target_line = target_line + i - 1
			break
		end
	end

	vim.fn.cursor(target_line, 1)
	vim.cmd("normal! zz") -- Center the view
end

-- Navigate to next slide
function M.next_slide()
	local current, _ = get_current_slide()
	M.go_to_slide(current + 1)
end

-- Navigate to previous slide
function M.previous_slide()
	local current, _ = get_current_slide()
	M.go_to_slide(current - 1)
end

-- Show slide count in statusline
function M.slide_status()
	local current, positions = get_current_slide()
	local total = #positions - 1
	return string.format("[Slide %d/%d]", current, total)
end

-- Create new slide after current
function M.new_slide()
	local current, positions = get_current_slide()
	local insert_line = positions[current + 1] - 1 -- Insert before the end marker

	-- If we're at the last slide, insert at the end
	if current == #positions - 1 then
		insert_line = vim.fn.line("$")
	end

	-- Insert empty lines and slide marker
	local new_content = { "", "", "", SLIDE_MARKER }
	vim.fn.append(insert_line, new_content)

	-- Move cursor to the second empty line (ready to type)
	vim.fn.cursor(insert_line + 2, 1)
	vim.cmd("startinsert")
end

-- Split slide at cursor position
function M.split_slide()
	local cursor_line = vim.fn.line(".")

	-- Insert slide marker above current line
	vim.fn.append(cursor_line - 1, { "", SLIDE_MARKER, "" })

	-- Move cursor to stay in the same relative position
	vim.fn.cursor(cursor_line + 3, 1)
end

-- Delete current slide
function M.delete_slide()
	local current, positions = get_current_slide()
	local total_slides = #positions - 1
	local frontmatter_end = get_frontmatter_end()

	if total_slides == 1 then
		vim.notify("Cannot delete the only slide", vim.log.levels.WARN)
		return
	end

	-- Don't delete frontmatter
	local start_line = positions[current]
	local end_line = positions[current + 1]

	-- If it's the first slide, start after the frontmatter
	if current == 1 then
		start_line = frontmatter_end
	else
		start_line = start_line + 1
	end

	-- Move cursor to the start of the slide
	vim.fn.cursor(start_line + 1, 1)

	-- Use normal mode delete to capture in register
	-- Calculate number of lines to delete
	local lines_to_delete = end_line - start_line

	-- Delete using dd command (into registers)
	if lines_to_delete > 0 then
		vim.cmd("normal! " .. lines_to_delete .. "dd")
	end

	-- Move to appropriate slide
	if current == total_slides then
		M.previous_slide()
	else
		-- Stay on current slide number (which is now the next slide)
		M.go_to_slide(current)
	end
end

-- Get slide content
local function get_slide_content(slide_num, positions, skip_pre_header)
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local frontmatter_end = get_frontmatter_end()
	local start_line = positions[slide_num] + 1
	local end_line = positions[slide_num + 1]

	-- For first slide, optionally skip content before first header
	if skip_pre_header and slide_num == 1 and start_line <= frontmatter_end + 1 then
		-- Find first header after frontmatter
		for i = frontmatter_end + 1, end_line - 1 do
			if i <= #lines and lines[i]:match("^#+ ") then
				start_line = i
				break
			end
		end
	end

	local slide_lines = {}
	for i = start_line, end_line - 1 do
		if i <= #lines then
			table.insert(slide_lines, lines[i])
		end
	end

	-- Remove the slide marker from the end if present
	if #slide_lines > 0 and slide_lines[#slide_lines]:match(SLIDE_PATTERN) then
		table.remove(slide_lines)
	end

	-- Trim trailing empty lines
	while #slide_lines > 0 and slide_lines[#slide_lines] == "" do
		table.remove(slide_lines)
	end

	return slide_lines
end

-- Move slide up
function M.move_slide_up()
	local current, positions = get_current_slide()

	if current == 1 then
		vim.notify("Already at the first slide", vim.log.levels.WARN)
		return
	end

	-- Get content of current and previous slides (skip pre-header for first slide)
	local current_content = get_slide_content(current, positions, current == 1)
	local prev_content = get_slide_content(current - 1, positions, current - 1 == 1)

	-- Calculate line ranges
	local prev_start = positions[current - 1] + 1
	local current_end = positions[current + 1] - 1

	-- Build new content: current, marker, previous
	local new_content = {}
	vim.list_extend(new_content, current_content)
	table.insert(new_content, "")
	table.insert(new_content, SLIDE_MARKER)
	table.insert(new_content, "")
	vim.list_extend(new_content, prev_content)

	-- Replace the two slides
	vim.api.nvim_buf_set_lines(0, prev_start - 1, current_end, false, new_content)

	-- Move cursor to the new position of the current slide
	M.previous_slide()
end

-- Move slide down
function M.move_slide_down()
	local current, positions = get_current_slide()
	local total_slides = #positions - 1

	if current == total_slides then
		vim.notify("Already at the last slide", vim.log.levels.WARN)
		return
	end

	-- Get content of current and next slides (skip pre-header for first slide)
	local current_content = get_slide_content(current, positions, current == 1)
	local next_content = get_slide_content(current + 1, positions, false)

	-- Calculate line ranges
	local current_start = positions[current] + 1
	local next_end = positions[current + 2] - 1

	-- Build new content: next, marker, current
	local new_content = {}
	vim.list_extend(new_content, next_content)
	table.insert(new_content, "")
	table.insert(new_content, SLIDE_MARKER)
	table.insert(new_content, "")
	vim.list_extend(new_content, current_content)

	-- Replace the two slides
	vim.api.nvim_buf_set_lines(0, current_start - 1, next_end, false, new_content)

	-- Move cursor to the new position of the current slide
	M.next_slide()
end

-- Yank current slide
function M.yank_slide()
	local current, positions = get_current_slide()
	local frontmatter_end = get_frontmatter_end()
	local total_slides = #positions - 1

	-- Calculate slide boundaries
	local start_line = positions[current] + 1
	local end_line = positions[current + 1] -- Include the slide marker

	-- For first slide, skip content before first header
	if current == 1 and start_line <= frontmatter_end + 1 then
		-- Find first header after frontmatter
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		for i = frontmatter_end + 1, end_line - 1 do
			if i <= #lines and lines[i]:match("^#+ ") then
				start_line = i
				break
			end
		end
	end

	-- For last slide, don't include the final buffer position
	if current == total_slides then
		end_line = positions[current + 1] - 1
	end

	-- Save current cursor position
	local save_cursor = vim.fn.getpos(".")

	-- Move cursor to the start of the slide
	vim.fn.cursor(start_line, 1)

	-- Calculate number of lines to yank (including the marker)
	local lines_to_yank = end_line - start_line + 1

	-- Yank using yy command (into registers)
	if lines_to_yank > 0 then
		vim.cmd("normal! " .. lines_to_yank .. "yy")
		vim.notify("Slide yanked (" .. lines_to_yank .. " lines)", vim.log.levels.INFO)
	end

	-- Return cursor to original position
	vim.fn.setpos(".", save_cursor)
end

-- Visually select current slide
function M.select_slide()
	local current, positions = get_current_slide()
	local frontmatter_end = get_frontmatter_end()
	local total_slides = #positions - 1

	-- Calculate slide boundaries
	local start_line = positions[current] + 1
	local end_line = positions[current + 1] -- Include the slide marker

	-- For first slide, skip content before first header
	if current == 1 and start_line <= frontmatter_end + 1 then
		-- Find first header after frontmatter
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		for i = frontmatter_end + 1, end_line - 1 do
			if i <= #lines and lines[i]:match("^#+ ") then
				start_line = i
				break
			end
		end
	end

	-- For last slide, don't go beyond the file
	if current == total_slides then
		end_line = math.min(positions[current + 1], vim.fn.line("$"))
	end

	-- Move cursor to start of slide
	vim.fn.cursor(start_line, 1)

	-- Enter visual line mode
	vim.cmd("normal! V")

	-- Move to end of slide (including the marker)
	vim.fn.cursor(end_line, 1)
end

-- Get slide titles for telescope picker
local function get_slide_titles()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local positions = get_slide_positions()
	local slides = {}

	for i = 1, #positions - 1 do
		local start_line = positions[i] + 1
		local end_line = positions[i + 1]
		local title = string.format("Slide %d", i)
		local preview_lines = {}

		-- Look for title in the slide
		for j = start_line, math.min(end_line - 1, start_line + 10) do
			if j <= #lines then
				local line = lines[j]
				-- Check for markdown headers
				if line:match("^#+ ") then
					title = line:gsub("^#+ ", "")
					break
				elseif j < #lines and lines[j + 1]:match("^=+$") then
					-- Setext style header
					title = line
					break
				end

				-- Collect preview lines
				if line:match("%S") then
					table.insert(preview_lines, line)
				end
			end
		end

		table.insert(slides, {
			index = i,
			title = title,
			start_line = start_line,
			preview = table.concat(preview_lines, " "):sub(1, 80) .. "...",
		})
	end

	return slides
end

-- Telescope slide picker
function M.slide_picker()
	local ok, telescope = pcall(require, "telescope")
	if not ok then
		vim.notify("Telescope not found", vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	local slides = get_slide_titles()

	pickers
		.new({}, {
			prompt_title = "Presenterm Slides",
			finder = finders.new_table({
				results = slides,
				entry_maker = function(entry)
					return {
						value = entry,
						display = string.format("%2d. %s", entry.index, entry.title),
						ordinal = entry.index .. " " .. entry.title .. " " .. entry.preview,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						M.go_to_slide(selection.value.index)
					end
				end)
				return true
			end,
		})
		:find()
end

-- Toggle +exec flag on code block
function M.toggle_exec()
	local cursor_line = vim.fn.line(".")
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	-- Find code block boundaries
	local start_line = nil
	local end_line = nil

	-- Search backwards for code block start
	for i = cursor_line, 1, -1 do
		if lines[i]:match("^```") then
			start_line = i
			break
		end
	end

	-- If no start found, not in a code block
	if not start_line then
		return
	end

	-- Search forwards for code block end
	for i = cursor_line, #lines do
		if i > start_line and lines[i]:match("^```") then
			end_line = i
			break
		end
	end

	-- If no end found, not in a valid code block
	if not end_line then
		return
	end

	-- Now we know we're inside a code block, toggle the +exec flag
	local code_fence = lines[start_line]
	if code_fence:match("%+exec") then
		-- Remove +exec flags
		code_fence = code_fence:gsub(" %+exec%w*", "")
	else
		-- Add +exec flag
		code_fence = code_fence .. " +exec"
	end

	vim.fn.setline(start_line, code_fence)
end

-- Count slides and estimate time
function M.presentation_stats()
	local _, positions = get_current_slide()
	local total_slides = #positions - 1
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	local word_count = 0
	local code_blocks = 0
	local exec_blocks = 0

	for _, line in ipairs(lines) do
		if line:match("^```") then
			code_blocks = code_blocks + 1
			if line:match("%+exec") then
				exec_blocks = exec_blocks + 1
			end
		else
			-- Simple word count
			for word in line:gmatch("%S+") do
				word_count = word_count + 1
			end
		end
	end

	-- Rough estimates
	local speaking_time = math.ceil(word_count / 150) -- 150 words per minute
	local demo_time = exec_blocks * 0.5 -- 30 seconds per exec block
	local total_time = speaking_time + demo_time

	local stats = {
		string.format("Slides: %d", total_slides),
		string.format("Words: %d", word_count),
		string.format("Code blocks: %d (%d executable)", code_blocks, exec_blocks),
		string.format("Estimated time: %d minutes", total_time),
	}

	vim.notify(table.concat(stats, "\n"), vim.log.levels.INFO)
end

-- Launch presenterm preview
function M.preview()
	local file = vim.fn.expand("%:p")
	if not file:match("%.md$") then
		vim.notify("Not a markdown file", vim.log.levels.ERROR)
		return
	end

	-- Save the file first
	vim.cmd("write")

	-- Check if we're in tmux
	if vim.env.TMUX then
		-- Launch in vertical tmux pane
		vim.fn.system('tmux split-window -h "presenterm ' .. file .. '"')
	else
		-- Fall back to neovim terminal
		vim.cmd("vsplit | terminal presenterm " .. file)
	end
end

-- Check if file is a presenterm presentation
local function is_presentation()
	-- Check for slide markers in the file
	local lines = vim.api.nvim_buf_get_lines(0, 0, math.min(100, vim.fn.line("$")), false)
	for _, line in ipairs(lines) do
		if line:match(SLIDE_PATTERN) then
			return true
		end
	end

	-- Check for presenterm front matter
	if lines[1] and lines[1]:match("^%-%-%-") then
		for i = 2, math.min(20, #lines) do
			if lines[i]:match("^%-%-%-") then
				break
			end
			if lines[i]:match("^title:") or lines[i]:match("^author:") then
				return true
			end
		end
	end

	return false
end

-- Interactive slide reordering
function M.interactive_reorder()
	local original_buf = vim.api.nvim_get_current_buf()
	local positions = get_slide_positions()
	local slides = {}
	local frontmatter_end = get_frontmatter_end()

	-- Get all slides content
	for i = 1, #positions - 1 do
		local slide_content = get_slide_content(i, positions)
		local title = string.format("Slide %d", i)

		-- Find title in slide content
		for _, line in ipairs(slide_content) do
			if line:match("^#+ ") then
				title = line:gsub("^#+ ", "")
				break
			end
		end

		table.insert(slides, {
			index = i,
			title = title,
			content = slide_content,
		})
	end

	-- Create reorder buffer
	vim.cmd("new")
	local reorder_buf = vim.api.nvim_get_current_buf()
	vim.bo[reorder_buf].filetype = "presenterm-reorder"
	vim.bo[reorder_buf].buftype = "nofile"
	vim.bo[reorder_buf].bufhidden = "wipe"
	vim.bo[reorder_buf].modifiable = true

	-- Display slides
	local display_lines = {
		"# Slide Reordering Mode",
		"# Use dd/p to move slides, Enter or :Apply to save, :q to cancel",
		"",
	}

	for _, slide in ipairs(slides) do
		table.insert(display_lines, string.format("%d. %s", slide.index, slide.title))
	end

	vim.api.nvim_buf_set_lines(reorder_buf, 0, -1, false, display_lines)

	-- Store original data
	vim.b[reorder_buf].original_buf = original_buf
	vim.b[reorder_buf].slides = slides
	vim.b[reorder_buf].frontmatter_end = frontmatter_end

	-- Apply reordering function
	local function apply_reorder()
		local lines = vim.api.nvim_buf_get_lines(reorder_buf, 0, -1, false)
		local new_order = {}

		-- Parse the new order
		for _, line in ipairs(lines) do
			local num = line:match("^(%d+)%.")
			if num then
				table.insert(new_order, tonumber(num))
			end
		end

		if #new_order ~= #slides then
			vim.notify("Error: Slide count mismatch", vim.log.levels.ERROR)
			return
		end

		-- Rebuild the presentation
		local all_lines = vim.api.nvim_buf_get_lines(original_buf, 0, -1, false)
		local new_lines = {}

		-- Add frontmatter if exists
		if frontmatter_end > 0 then
			for i = 1, frontmatter_end do
				table.insert(new_lines, all_lines[i])
			end
			table.insert(new_lines, "")
		end

		-- Add slides in new order
		for i, slide_idx in ipairs(new_order) do
			local slide = slides[slide_idx]
			vim.list_extend(new_lines, slide.content)

			-- Add slide marker if not the last slide
			if i < #new_order then
				table.insert(new_lines, "")
				table.insert(new_lines, SLIDE_MARKER)
				table.insert(new_lines, "")
			end
		end

		-- Apply changes
		vim.api.nvim_buf_set_lines(original_buf, 0, -1, false, new_lines)
		vim.notify("Slides reordered successfully", vim.log.levels.INFO)
		vim.cmd("close")
	end

	-- Create custom commands for this buffer
	vim.api.nvim_buf_create_user_command(reorder_buf, "Apply", function()
		apply_reorder()
	end, { desc = "Apply slide reordering" })

	vim.api.nvim_buf_create_user_command(reorder_buf, "A", function()
		apply_reorder()
	end, { desc = "Apply slide reordering" })

	-- Keybindings
	vim.keymap.set("n", "<CR>", function()
		apply_reorder()
	end, { buffer = reorder_buf, desc = "Apply reordering" })

	vim.keymap.set("n", "<leader>w", function()
		apply_reorder()
	end, { buffer = reorder_buf, desc = "Apply reordering" })

	-- Add help
	vim.keymap.set("n", "?", function()
		vim.notify(
			"Slide Reordering:\n"
				.. "• dd       - cut slide\n"
				.. "• p        - paste slide below\n"
				.. "• P        - paste slide above\n"
				.. "• Enter    - apply changes\n"
				.. "• :Apply   - apply changes\n"
				.. "• :A       - apply changes (short)\n"
				.. "• <leader>w - apply changes\n"
				.. "• :q       - cancel",
			vim.log.levels.INFO
		)
	end, { buffer = reorder_buf, desc = "Show help" })
end

-- Run current code block (if it has +exec)
function M.run_code_block()
	local cursor_line = vim.fn.line(".")
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	-- Find code block boundaries
	local start_line = nil
	local end_line = nil
	local lang = nil

	-- Search backwards for code block start
	for i = cursor_line, 1, -1 do
		if lines[i]:match("^```") then
			start_line = i
			lang = lines[i]:match("^```(%w+)")
			break
		end
	end

	if not start_line then
		vim.notify("Not inside a code block", vim.log.levels.WARN)
		return
	end

	-- Check if it has +exec
	if not lines[start_line]:match("%+exec") then
		vim.notify("Code block doesn't have +exec flag", vim.log.levels.WARN)
		return
	end

	-- Find code block end
	for i = start_line + 1, #lines do
		if lines[i]:match("^```") then
			end_line = i
			break
		end
	end

	if not end_line then
		vim.notify("Code block not properly closed", vim.log.levels.WARN)
		return
	end

	-- Extract code
	local code_lines = {}
	for i = start_line + 1, end_line - 1 do
		table.insert(code_lines, lines[i])
	end

	-- Execute based on language
	local code = table.concat(code_lines, "\n")
	if lang == "bash" or lang == "sh" then
		-- Create a temporary file
		local tmpfile = vim.fn.tempname() .. ".sh"
		vim.fn.writefile(code_lines, tmpfile)

		-- Execute in a new terminal
		vim.cmd("split | terminal bash " .. tmpfile)
		vim.cmd("resize 15")
	else
		vim.notify("Execution not supported for language: " .. (lang or "unknown"), vim.log.levels.WARN)
	end
end

-- Setup buffer-local keymaps for presentation files
local function setup_buffer_keymaps()
	-- Check if already activated to prevent duplicate setup
	if vim.b.presenterm_active then
		return
	end

	local opts = { buffer = true }

	-- Navigation
	vim.keymap.set("n", "]s", M.next_slide, vim.tbl_extend("force", opts, { desc = "Next slide" }))
	vim.keymap.set("n", "[s", M.previous_slide, vim.tbl_extend("force", opts, { desc = "Previous slide" }))

	-- Slide management
	vim.keymap.set("n", "<leader>sd", M.delete_slide, vim.tbl_extend("force", opts, { desc = "Delete slide (cut)" }))
	vim.keymap.set("n", "<leader>sy", M.yank_slide, vim.tbl_extend("force", opts, { desc = "Yank slide (copy)" }))
	vim.keymap.set("n", "<leader>sv", M.select_slide, vim.tbl_extend("force", opts, { desc = "Visually select slide" }))
	vim.keymap.set("n", "<leader>ss", M.split_slide, vim.tbl_extend("force", opts, { desc = "Split slide" }))
	vim.keymap.set("n", "<leader>sl", M.slide_picker, vim.tbl_extend("force", opts, { desc = "List slides" }))

	-- Slide movement
	vim.keymap.set("n", "<leader>sk", M.move_slide_up, vim.tbl_extend("force", opts, { desc = "Move slide up" }))
	vim.keymap.set("n", "<leader>sj", M.move_slide_down, vim.tbl_extend("force", opts, { desc = "Move slide down" }))

	-- Code blocks
	vim.keymap.set("n", "<leader>se", M.toggle_exec, vim.tbl_extend("force", opts, { desc = "Toggle +exec" }))
	vim.keymap.set("n", "<leader>sr", M.run_code_block, vim.tbl_extend("force", opts, { desc = "Run code block" }))

	-- Preview and stats
	vim.keymap.set("n", "<leader>sP", M.preview, vim.tbl_extend("force", opts, { desc = "Preview presentation" }))
	vim.keymap.set(
		"n",
		"<leader>sc",
		M.presentation_stats,
		vim.tbl_extend("force", opts, { desc = "Presentation stats" })
	)

	-- Interactive reordering
	vim.keymap.set(
		"n",
		"<leader>sR",
		M.interactive_reorder,
		vim.tbl_extend("force", opts, { desc = "Reorder slides interactively" })
	)

	-- Set buffer variable to indicate presenterm is active
	vim.b.presenterm_active = true

	-- Add slide indicator to statusline if possible
	if vim.b.presenterm_active then
		vim.notify("Presenterm mode activated", vim.log.levels.INFO)
	end
end

-- Show active keybindings
function M.show_keybindings()
	if not vim.b.presenterm_active then
		vim.notify("Presenterm mode is not active in this buffer", vim.log.levels.WARN)
		return
	end

	local bindings = {
		"# Presenterm Keybindings",
		"",
		"## Navigation",
		"]s          - Next slide (jump to header)",
		"[s          - Previous slide (jump to header)",
		"<leader>sl  - List slides (Telescope)",
		"",
		"## Slide Management",
		"<leader>sd  - Delete slide (cut to register)",
		"<leader>sy  - Yank slide (copy to register)",
		"<leader>sv  - Visually select slide",
		"<leader>ss  - Split slide at cursor",
		"<leader>sk  - Move slide up",
		"<leader>sj  - Move slide down",
		"<leader>sR  - Reorder slides interactively",
		"",
		"## Code Blocks",
		"<leader>se  - Toggle +exec flag",
		"<leader>sr  - Run current code block",
		"",
		"## Preview & Analysis",
		"<leader>sP  - Preview presentation (tmux pane)",
		"<leader>sc  - Show presentation stats",
	}

	-- Create floating window
	local width = math.min(50, vim.o.columns - 4)
	local height = math.min(#bindings + 2, vim.o.lines - 4)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"

	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		border = "rounded",
		style = "minimal",
		title = " Presenterm Keybindings ",
		title_pos = "center",
	}

	local win = vim.api.nvim_open_win(buf, true, win_opts)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, bindings)
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "markdown"

	-- Close on any key
	vim.keymap.set("n", "<Esc>", ":close<CR>", { buffer = buf, silent = true })
	vim.keymap.set("n", "q", ":close<CR>", { buffer = buf, silent = true })
end

-- Manually activate presenterm mode for current buffer
function M.activate()
	setup_buffer_keymaps()
end

-- Setup function to create autocommands
function M.setup()
	-- Auto-activate for presentation files
	vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
		pattern = { "presentation.md", "*/presentations/*.md", "*/slides/*.md" },
		callback = function()
			-- Schedule to run after buffer is fully loaded
			vim.schedule(function()
				if is_presentation() then
					setup_buffer_keymaps()
				end
			end)
		end,
	})

	-- Also check when entering a markdown buffer
	vim.api.nvim_create_autocmd("BufEnter", {
		pattern = "*.md",
		callback = function()
			-- Only auto-activate for files named presentation.md
			local filename = vim.fn.expand("%:t")
			if filename == "presentation.md" and is_presentation() then
				setup_buffer_keymaps()
			end
		end,
	})

	-- Create user command to manually activate
	vim.api.nvim_create_user_command("PresenterMode", function()
		M.activate()
	end, { desc = "Activate presenterm mode for current buffer" })

	-- Create command to show keybindings
	vim.api.nvim_create_user_command("PresenterBindings", function()
		M.show_keybindings()
	end, { desc = "Show presenterm keybindings" })
end

return M
