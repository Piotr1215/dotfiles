-- ~/.config/nvim/lua/user_functions/telescope_projects.lua
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local previewers = require "telescope.previewers"

local M = {}

-- Load directories from shared config file
local function load_project_dirs()
  local dirs = {}
  local config_file = vim.fn.expand "~/dev/dotfiles/project_dirs.txt"
  local file = io.open(config_file, "r")
  if file then
    for line in file:lines() do
      local trimmed = line:match "^%s*(.-)%s*$"
      if trimmed ~= "" then
        table.insert(dirs, vim.fn.expand(trimmed))
      end
    end
    file:close()
  end
  return dirs
end

local PROJECT_DIRS = load_project_dirs()

local function get_projects_file_path()
  return vim.fn.expand "~/dev/dotfiles/projects.txt"
end

local function load_projects()
  local projects_file = get_projects_file_path()
  local projects = {}

  local file = io.open(projects_file, "r")
  if not file then
    vim.notify("Could not open projects file: " .. projects_file, vim.log.levels.ERROR)
    return {}
  end

  for line in file:lines() do
    local trimmed = line:match "^%s*(.-)%s*$"
    if trimmed ~= "" then
      table.insert(projects, trimmed)
    end
  end
  file:close()

  return projects
end

local function get_project_files_async(project_name, callback)
  local project_tag = "PROJECT: " .. project_name

  local cmd = {
    "rg",
    "--files-with-matches",
    "--no-messages",
    project_tag,
    "--glob",
    "!.git",
    "--glob",
    "!node_modules",
    "--glob",
    "!.cache",
    "--glob",
    "!.local/share",
    "--glob",
    "!.cargo",
    "--glob",
    "!.rustup",
    "--glob",
    "!venv",
    "--glob",
    "!__pycache__",
    "--glob",
    "!.npm",
    "--glob",
    "!.yarn",
    "--glob",
    "!dist",
    "--glob",
    "!build",
    "--glob",
    "!.vscode",
    "--glob",
    "!.idea",
    "--glob",
    "!target",
    "--glob",
    "!*.log",
    "--glob",
    "!*.tmp",
  }
  for _, dir in ipairs(PROJECT_DIRS) do
    table.insert(cmd, dir)
  end

  local files = {}
  local job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      for _, line in ipairs(data) do
        if line and line ~= "" then
          local trimmed = line:match "^%s*(.-)%s*$"
          if trimmed ~= "" then
            table.insert(files, trimmed)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      vim.schedule(function()
        callback(files)
      end)
    end,
  })

  if job_id <= 0 then
    callback {}
  end
end

-- Synchronous version for project counting (fast enough for preview)
local function get_project_files_sync(project_name)
  local project_tag = "PROJECT: " .. project_name
  local dirs = table.concat(PROJECT_DIRS, " ")
  local handle = io.popen(
    "rg --files-with-matches --no-messages '"
      .. project_tag
      .. "' "
      .. "--glob '!.git' --glob '!node_modules' --glob '!.cache' "
      .. "--glob '!.local/share' --glob '!.cargo' --glob '!.rustup' "
      .. "--glob '!venv' --glob '!__pycache__' --glob '!.npm' "
      .. "--glob '!.yarn' --glob '!dist' --glob '!build' "
      .. "--glob '!.vscode' --glob '!.idea' --glob '!target' "
      .. "--glob '!*.log' --glob '!*.tmp' "
      .. dirs
  )

  if not handle then
    return {}
  end

  local files = {}
  for line in handle:lines() do
    local trimmed = line:match "^%s*(.-)%s*$"
    if trimmed ~= "" then
      table.insert(files, trimmed)
    end
  end
  handle:close()

  return files
end

local function count_project_files(project_name)
  local files = get_project_files_sync(project_name)
  return #files
end

-- Custom previewer for projects showing file count and sample files
local function project_previewer()
  return previewers.new_buffer_previewer {
    title = "Project Info",
    define_preview = function(self, entry, status)
      local project_name = entry.value
      local files = get_project_files_sync(project_name)
      local count = #files

      local lines = {
        "Project: " .. project_name,
        "Files: " .. count,
        "",
        "Files containing PROJECT: " .. project_name .. ":",
      }

      for i, file in ipairs(files) do
        if i <= 10 then -- Show max 10 files in preview
          table.insert(lines, "  " .. file)
        elseif i == 11 then
          table.insert(lines, "  ... and " .. (count - 10) .. " more files")
          break
        end
      end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
    end,
  }
end

-- Custom previewer for project files showing file content
local function file_previewer()
  return previewers.new_buffer_previewer {
    title = "File Preview",
    define_preview = function(self, entry, status)
      local file_path = entry.value

      -- Read file content
      local file = io.open(file_path, "r")
      if not file then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Could not open file: " .. file_path })
        return
      end

      local lines = {}
      local line_num = 0
      for line in file:lines() do
        line_num = line_num + 1
        table.insert(lines, string.format("%3d: %s", line_num, line))
        if line_num >= 100 then -- Limit preview to 100 lines
          table.insert(lines, "... (truncated)")
          break
        end
      end
      file:close()

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

      -- Set filetype for syntax highlighting
      local ft = vim.filetype.match { filename = file_path }
      if ft then
        vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", ft)
      end
    end,
  }
end

function M.show_project_files(project_name)
  -- Start async search and show picker when results arrive
  get_project_files_async(project_name, function(files)
    if #files == 0 then
      vim.notify("No files found for project: " .. project_name, vim.log.levels.WARN)
      return
    end

    pickers
      .new({}, {
        prompt_title = "Files for Project: " .. project_name,
        finder = finders.new_table {
          results = files,
          entry_maker = function(entry)
            return {
              value = entry,
              display = vim.fn.fnamemodify(entry, ":~:."),
              ordinal = entry,
            }
          end,
        },
        previewer = file_previewer(),
        sorter = conf.generic_sorter {},
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            vim.cmd("edit " .. selection.value)
          end)

          -- Multi-select and open in splits
          map("i", "<C-v>", function()
            local current_selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            vim.cmd("vsplit " .. current_selection.value)
          end)

          map("i", "<C-x>", function()
            local current_selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            vim.cmd("split " .. current_selection.value)
          end)

          -- Open multiple selected files
          map("i", "<C-q>", function()
            local current_picker = action_state.get_current_picker(prompt_bufnr)
            local selections = current_picker:get_multi_selection()
            actions.close(prompt_bufnr)

            if #selections > 0 then
              for _, sel in ipairs(selections) do
                vim.cmd("edit " .. sel.value)
              end
            else
              local current_selection = action_state.get_selected_entry()
              vim.cmd("edit " .. current_selection.value)
            end
          end)

          -- Open selected files in multi-pane layout (Alt+a) - manual mapping
          map("i", "<M-a>", function()
            local current_picker = action_state.get_current_picker(prompt_bufnr)

            -- Get multi-selected entries first
            local multi_selections = current_picker:get_multi_selection()
            local selected_entries = {}

            if #multi_selections > 0 then
              -- User has made multi-selections, use those
              for _, entry in ipairs(multi_selections) do
                table.insert(selected_entries, entry.value)
              end
            else
              -- No multi-selections, use current selection
              local current_selection = action_state.get_selected_entry()
              if current_selection then
                table.insert(selected_entries, current_selection.value)
              end
            end

            actions.close(prompt_bufnr)

            if #selected_entries == 0 then
              vim.notify("No files selected", vim.log.levels.WARN)
              return
            end

            -- Limit the number of files to prevent "too many open files" error
            local max_files = 20
            if #selected_entries > max_files then
              vim.notify(
                "Too many files selected (" .. #selected_entries .. "). Opening first " .. max_files .. " files.",
                vim.log.levels.WARN
              )
              local truncated = {}
              for i = 1, max_files do
                table.insert(truncated, selected_entries[i])
              end
              selected_entries = truncated
            end

            if #selected_entries == 1 then
              vim.cmd("edit " .. vim.fn.fnameescape(selected_entries[1]))
            elseif #selected_entries == 2 then
              vim.cmd("edit " .. vim.fn.fnameescape(selected_entries[1]))
              vim.cmd("vs " .. vim.fn.fnameescape(selected_entries[2]))
            else
              vim.cmd("edit " .. vim.fn.fnameescape(selected_entries[1]))
              vim.cmd("vs " .. vim.fn.fnameescape(selected_entries[2]))
              if #selected_entries >= 3 then
                vim.cmd("split " .. vim.fn.fnameescape(selected_entries[3]))
              end
              -- Open remaining files in tabs, but with a reasonable limit
              local max_tabs = math.min(10, #selected_entries - 3) -- Max 10 additional tabs
              for i = 4, 3 + max_tabs do
                if selected_entries[i] then
                  vim.cmd("tabedit " .. vim.fn.fnameescape(selected_entries[i]))
                end
              end

              if #selected_entries > 13 then
                vim.notify(
                  "Opened first 13 files in panes/tabs. " .. (#selected_entries - 13) .. " files skipped.",
                  vim.log.levels.INFO
                )
              end
            end
          end)

          return true
        end,
      })
      :find()
  end)
end

function M.project_picker()
  local projects = load_projects()

  if #projects == 0 then
    vim.notify("No projects found in projects.txt", vim.log.levels.WARN)
    return
  end

  pickers
    .new({}, {
      prompt_title = "Select Project",
      finder = finders.new_table {
        results = projects,
        entry_maker = function(entry)
          local file_count = count_project_files(entry)
          return {
            value = entry,
            display = string.format("%-30s (%d files)", entry, file_count),
            ordinal = entry,
          }
        end,
      },
      previewer = project_previewer(),
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          M.show_project_files(selection.value)
        end)
        return true
      end,
    })
    :find()
end

function M.crawl_projects()
  local projects_file = get_projects_file_path()

  -- Backup existing projects.txt
  local backup_file = projects_file .. ".backup." .. os.date "%Y%m%d_%H%M%S"
  local backup_cmd = "cp '" .. projects_file .. "' '" .. backup_file .. "'"
  os.execute(backup_cmd)

  vim.notify("Crawling for PROJECT: references...", vim.log.levels.INFO)

  -- Use rg to find all PROJECT: references efficiently
  local dirs = table.concat(PROJECT_DIRS, " ")
  local rg_cmd = [[rg "PROJECT:\s*(\S+)" --only-matching --no-filename --no-line-number ]]
    .. [[--ignore-case --type-not binary ]]
    .. [[--glob '!.git' --glob '!node_modules' --glob '!.cache' ]]
    .. [[--glob '!.local/share' --glob '!.cargo' --glob '!.rustup' ]]
    .. [[--glob '!venv' --glob '!__pycache__' --glob '!.npm' ]]
    .. [[--glob '!.yarn' --glob '!dist' --glob '!build' ]]
    .. [[--glob '!.vscode' --glob '!.idea' --glob '!target' ]]
    .. [[--glob '!*.log' --glob '!*.tmp' ]]
    .. dirs

  local handle = io.popen(rg_cmd)
  if not handle then
    vim.notify("Failed to execute rg command", vim.log.levels.ERROR)
    return
  end

  -- Parse project names from rg output
  local found_projects = {}
  for line in handle:lines() do
    -- Handle "PROJECT: project_name" format
    local project_name = line:match "PROJECT:%s*(.+)"
    if project_name then
      -- Trim whitespace
      project_name = project_name:match "^%s*(.-)%s*$"
      if project_name and project_name ~= "" then
        found_projects[project_name] = true
      end
    end
  end
  handle:close()

  -- Load existing projects
  local existing_projects = {}
  local existing_list = load_projects()
  for _, project in ipairs(existing_list) do
    existing_projects[project] = true
  end

  -- Find new projects
  local new_projects = {}
  for project, _ in pairs(found_projects) do
    if not existing_projects[project] then
      table.insert(new_projects, project)
    end
  end

  -- Sort new projects
  table.sort(new_projects)

  if #new_projects == 0 then
    vim.notify("No new projects found. Backup saved to: " .. backup_file, vim.log.levels.INFO)
    return
  end

  -- Show preview of what will be added
  local preview_lines = { "Found " .. #new_projects .. " new projects:", "" }
  for _, project in ipairs(new_projects) do
    table.insert(preview_lines, "  " .. project)
  end
  table.insert(preview_lines, "")
  table.insert(preview_lines, "Add these to projects.txt? (y/N)")

  -- Create a simple confirmation dialog
  local choice = vim.fn.input(table.concat(preview_lines, "\n"))

  if choice:lower() ~= "y" and choice:lower() ~= "yes" then
    vim.notify("Cancelled. Backup saved to: " .. backup_file, vim.log.levels.INFO)
    return
  end

  -- Append new projects to file
  local file = io.open(projects_file, "a")
  if not file then
    vim.notify("Failed to open projects file for writing", vim.log.levels.ERROR)
    return
  end

  for _, project in ipairs(new_projects) do
    file:write(project .. "\n")
  end
  file:close()

  vim.notify(
    "Added "
      .. #new_projects
      .. " new projects. Total found: "
      .. (#existing_list + #new_projects)
      .. ". Backup saved to: "
      .. backup_file,
    vim.log.levels.INFO
  )
end

-- Create user commands
vim.api.nvim_create_user_command("ProjectFiles", function()
  M.project_picker()
end, { desc = "Browse files by project" })

vim.api.nvim_create_user_command("ProjectFilesForCurrent", function()
  -- Try to detect project from current buffer
  local current_line = vim.api.nvim_get_current_line()
  local project_pattern = "PROJECT:%s*(%S+)"
  local project_name = current_line:match(project_pattern)

  if project_name then
    M.show_project_files(project_name)
  else
    -- Fallback to project picker
    M.project_picker()
  end
end, { desc = "Show files for project on current line or pick project" })

return M
