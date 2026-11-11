-- Keep the same editor and pane while Twoy changes selection.
local current = vim.env.HANDOFF_UUID
local pinned = vim.env.HANDOFF_PINNED == "1" and current or nil
local peeking = false
local script = vim.env.HANDOFF_ROOT .. "/__handoff_floater.sh"
local save_script = vim.env.HANDOFF_SAVE_SCRIPT
local pending_saves = {}
local DETAILS_START = "<!-- begin task details -->"
local DETAILS_END = "<!-- end task details -->"
local generated = {}

local function project_path(path)
	local uuid = path:match("/taskwarrior/briefs/([%x%-]+)/project%-status%.md$")
	return uuid ~= nil and #uuid == 36
end

generated[current] = project_path(vim.api.nvim_buf_get_name(0))

-- Mark each line inside a Markdown fence, the fence lines included.
local function fence_states(lines)
	local states, fence = {}, ""
	for index, line in ipairs(lines) do
		local marker, suffix = line:match("^%s*(`+)(.*)$")
		if not marker then
			marker, suffix = line:match("^%s*(~+)(.*)$")
		end
		local fenced = fence ~= ""
		if marker and #marker >= 3 then
			if fence == "" then
				fence, fenced = marker, true
			elseif marker:sub(1, 1) == fence:sub(1, 1) and #marker >= #fence and suffix:match("^%s*$") then
				fence = ""
			end
		end
		states[index] = fenced
	end
	return states
end

-- Regular tasks carry a generated details sidecar; handoff rows have none.
-- The editor owns the open buffer, so it splices the sidecar in itself
-- rather than letting a background writer replace text being edited.
local function refresh_details(buf)
	local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p")
	local sidecar = vim.fn.fnamemodify(path, ":h") .. "/.task-details.md"
	local wanted = {}
	if vim.fn.filereadable(sidecar) == 1 then
		wanted = vim.fn.readfile(sidecar)
		table.insert(wanted, 1, DETAILS_START)
		table.insert(wanted, DETAILS_END)
	end
	local was_modified = vim.bo[buf].modified
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local first, last
	for index, line in ipairs(lines) do
		if not first and line == DETAILS_START then
			first = index
		elseif first and line == DETAILS_END then
			last = index
			break
		end
	end
	if first and last then
		if vim.deep_equal(vim.list_slice(lines, first, last), wanted) then
			return
		end
		if #wanted == 0 then
			local from = first - 1
			if from >= 1 and lines[from] == "" then
				from = from - 1
			end
			vim.api.nvim_buf_set_lines(buf, from, last, false, {})
		else
			vim.api.nvim_buf_set_lines(buf, first - 1, last, false, wanted)
		end
	elseif #wanted > 0 then
		local states, title_line = fence_states(lines), 0
		for index, line in ipairs(lines) do
			if not states[index] and line:match("^#%s") then
				title_line = index
				break
			end
		end
		if title_line > 0 then
			table.insert(wanted, 1, "")
		else
			table.insert(wanted, "")
		end
		vim.api.nvim_buf_set_lines(buf, title_line, title_line, false, wanted)
	else
		return
	end
	-- Viewing a task should not leave the buffer modified; pending edits stay unsaved.
	if not was_modified then
		vim.api.nvim_buf_call(buf, function()
			vim.cmd("silent update")
		end)
	end
end

-- Tab hands the keyboard back to the task list and leaves the brief open.
local function focus_list()
	vim.system({ script, "focus-list", current, vim.env.HANDOFF_ORIGIN })
end

local function configure_brief_buffer(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p")
	local project = project_path(path)
	if not project and not path:match("/taskwarrior/briefs/[%x%-]+/brief%.md$") then
		return
	end
	vim.keymap.set("n", "<Tab>", focus_list, { buffer = buf, desc = "Focus the task list, keep the brief open" })
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modeline = false
	vim.bo[buf].readonly = project
	vim.bo[buf].modifiable = not project
	if project then
		vim.bo[buf].autoread = true
	end
	local window = vim.fn.bufwinid(buf)
	if window ~= -1 then
		vim.wo[window].wrap = true
		vim.wo[window].linebreak = true
	end
	if project then
		vim.cmd("silent checktime")
		return
	end
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local has_comments, fence, title_line = false, "", 0
	for index, line in ipairs(lines) do
		local marker, suffix = line:match("^%s*(`+)(.*)$")
		if not marker then
			marker, suffix = line:match("^%s*(~+)(.*)$")
		end
		local fenced = fence ~= ""
		if marker and #marker >= 3 then
			if fence == "" then
				fence, fenced = marker, true
			elseif marker:sub(1, 1) == fence:sub(1, 1) and #marker >= #fence and suffix:match("^%s*$") then
				fence = ""
			end
		end
		if not fenced and line:match("^##%s+My comments%s*$") then
			has_comments = true
			break
		end
		if not fenced and title_line == 0 and line:match("^#%s") then
			title_line = index
		end
	end
	if not has_comments then
		vim.api.nvim_buf_set_lines(buf, title_line, title_line, false, { "", "## My comments", "" })
	end
	refresh_details(buf)
end

local function save_brief(uuid)
	if generated[uuid] or not save_script then
		return true
	end
	local result = vim.system({ "python3", save_script, "save", uuid }, { text = true }):wait()
	if result.code ~= 0 then
		pending_saves[uuid] = true
		vim.notify(result.stderr, vim.log.levels.ERROR)
		return false
	end
	pending_saves[uuid] = nil
	return true
end

configure_brief_buffer()
if save_script then
	vim.schedule(function()
		save_brief(current)
	end)
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
	callback = function(event)
		local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(event.buf), ":p")
		local uuid = path:match("/taskwarrior/briefs/([%x%-]+)/brief%.md$")
		if not uuid or #uuid ~= 36 then
			return
		end
		configure_brief_buffer(event.buf)
		if event.event == "BufWritePost" then
			save_brief(uuid)
		end
	end,
})

local function prepare_uuid(uuid)
	local result = vim.system({ script, "prepare", uuid, vim.env.HANDOFF_ORIGIN }, { text = true }):wait()
	if result.code ~= 0 then
		error(result.stderr)
	end
	local path = vim.trim(result.stdout)
	generated[uuid] = project_path(path)
	if save_script and not generated[uuid] then
		local baseline = vim.system({ "python3", save_script, "init", uuid }, { text = true }):wait()
		if baseline.code ~= 0 then
			error(baseline.stderr)
		end
		if not save_brief(uuid) then
			error("Could not deliver a pending handoff comment; the saved event is retained for retry")
		end
	end
	return path
end

function _G.HandoffCurrent()
	return current
end

function _G.HandoffSwitch(uuid, refresh)
	if uuid == current and not refresh then
		return true
	end
	vim.cmd("silent update")
	if pending_saves[current] and not save_brief(current) then
		error("Could not deliver the saved handoff comment; the event is retained for retry")
	end
	local path = prepare_uuid(uuid)
	if uuid == current and path == vim.api.nvim_buf_get_name(0) then
		vim.cmd("checktime")
		if not generated[uuid] then
			refresh_details(vim.api.nvim_get_current_buf())
		end
	else
		vim.cmd.edit(vim.fn.fnameescape(path))
		configure_brief_buffer()
	end
	current = uuid
	return true
end

-- The background project refresh atomically replaces this generated file.
-- Check only the open generated buffer; no task export or source polling.
local refresh_timer = vim.uv.new_timer()
refresh_timer:start(
	1000,
	1000,
	vim.schedule_wrap(function()
		local buf = vim.api.nvim_get_current_buf()
		if project_path(vim.api.nvim_buf_get_name(buf)) and not vim.bo[buf].modified then
			vim.cmd("silent checktime")
		end
	end)
)

-- The task list selected another row. Answer 1 when the brief now shows that
-- task, so the launcher moves the pane under the row, or 0 when it keeps its
-- own: pinned, or holding an edit that did not save. A failed save leaves the
-- edit in the file and the pending event for retry.
function _G.HandoffSelection(uuid)
	if pinned and not peeking then
		return 0
	end
	local ok, err = pcall(HandoffSwitch, uuid)
	if not ok then
		vim.notify("Brief stays on its task: " .. tostring(err), vim.log.levels.ERROR)
		return 0
	end
	return 1
end

function _G.HandoffPin(uuid)
	pinned = uuid
	peeking = false
	return HandoffSwitch(uuid, true)
end

function _G.HandoffToggle(uuid)
	if pinned then
		peeking = not peeking
		return HandoffSwitch(peeking and uuid or pinned, true)
	end
	return HandoffHide()
end

function _G.HandoffHide()
	vim.cmd("silent update")
	if pending_saves[current] and not save_brief(current) then
		error("Could not deliver the saved handoff comment; the event is retained for retry")
	end
	-- Let the remote-expr response reach the launcher before Neovim exits.
	vim.defer_fn(function()
		vim.cmd("qa")
	end, 100)
	return true
end

local watcher = vim.fn.jobstart({ script, "watch", current, vim.env.HANDOFF_ORIGIN })
vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		refresh_timer:stop()
		refresh_timer:close()
		if pending_saves[current] then
			save_brief(current)
		end
		vim.fn.jobstop(watcher)
	end,
})
