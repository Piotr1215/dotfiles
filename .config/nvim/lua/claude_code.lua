-- Claude Code integration for Neovim
-- Provides helpers when editing Claude Code CLI input buffer

local M = {}

-- Get the original working directory (before opening temp file)
local function get_original_dir()
  return vim.fn.environ().PWD or vim.fn.getcwd()
end

-- Run command in original directory
local function run_in_original_dir(cmd)
  local original_dir = get_original_dir()
  local full_cmd = string.format("cd %s && %s", vim.fn.shellescape(original_dir), cmd)
  return vim.fn.systemlist(full_cmd)
end

-- Check if we're in Claude Code environment
function M.is_claude_code_env()
  return vim.fn.environ().CLAUDE_CODE_ENTRYPOINT == "cli"
end

-- Insert git diff at cursor
function M.insert_git_diff()
  local diff = run_in_original_dir "git diff"
  if #diff == 0 or (diff == 1 and diff[1] == "") then
    vim.notify("No unstaged changes", vim.log.levels.INFO)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]

  -- Insert with markdown formatting
  local lines = { "Here are my recent changes:", "", "```diff" }
  vim.list_extend(lines, diff)
  vim.list_extend(lines, { "```", "" })

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)
end

-- Insert git diff for specific file
function M.insert_file_diff(filepath)
  filepath = filepath or vim.fn.expand "%:p"
  local diff = run_in_original_dir(string.format("git diff -- %s", vim.fn.shellescape(filepath)))

  if #diff == 0 or (diff == 1 and diff[1] == "") then
    vim.notify("No changes in " .. vim.fn.fnamemodify(filepath, ":."), vim.log.levels.INFO)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]

  local lines = {
    string.format("Changes in %s:", vim.fn.fnamemodify(filepath, ":.")),
    "",
    "```diff",
  }
  vim.list_extend(lines, diff)
  vim.list_extend(lines, { "```", "" })

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)
end

-- Insert git status
function M.insert_git_status()
  local status = run_in_original_dir "git status --short"

  if #status == 0 or (status == 1 and status[1] == "") then
    vim.notify("Working tree clean", vim.log.levels.INFO)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]

  local lines = { "Git status:", "", "```" }
  vim.list_extend(lines, status)
  vim.list_extend(lines, { "```", "" })

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)
end

-- Insert file paths with telescope picker (multi-select)
function M.insert_file_paths()
  local has_telescope, pickers = pcall(require, "telescope.pickers")
  if not has_telescope then
    vim.notify("Telescope not found", vim.log.levels.ERROR)
    return
  end

  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  -- Get original directory
  local original_dir = vim.fn.environ().PWD or vim.fn.getcwd()

  local selected_files = {}

  pickers
    .new({ cwd = original_dir }, {
      prompt_title = "Select Files (Tab=multi, Enter=done)",
      finder = finders.new_oneshot_job({ "fd", "--type", "f" }, { cwd = original_dir }),
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr, map)
        -- Multi-select with Tab
        actions.toggle_selection:enhance {
          post = function()
            local current_picker = action_state.get_current_picker(prompt_bufnr)
            local selections = current_picker:get_multi_selection()
            selected_files = {}
            for _, entry in ipairs(selections) do
              table.insert(selected_files, entry[1])
            end
          end,
        }

        -- Insert on Enter
        actions.select_default:replace(function()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          local selections = current_picker:get_multi_selection()

          -- If nothing multi-selected, use current selection
          if #selections == 0 then
            local selection = action_state.get_selected_entry()
            if selection then
              table.insert(selected_files, selection[1])
            end
          else
            selected_files = {}
            for _, entry in ipairs(selections) do
              table.insert(selected_files, entry[1])
            end
          end

          actions.close(prompt_bufnr)

          if #selected_files > 0 then
            local cursor = vim.api.nvim_win_get_cursor(0)
            local row = cursor[1]

            local lines = { "Please read these files:" }
            for _, filepath in ipairs(selected_files) do
              table.insert(lines, "- " .. filepath)
            end
            table.insert(lines, "")

            vim.api.nvim_buf_set_lines(0, row, row, false, lines)
          end
        end)
        return true
      end,
    })
    :find()
end

-- Insert recent git log
function M.insert_git_log(count)
  count = count or 10
  local log = run_in_original_dir(string.format("git log --oneline -%d", count))

  if #log == 0 then
    vim.notify("No git history", vim.log.levels.INFO)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]

  local lines = { "Recent commits:", "", "```" }
  vim.list_extend(lines, log)
  vim.list_extend(lines, { "```", "" })

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)
end

-- Insert current branch name
function M.insert_branch()
  local branch = run_in_original_dir("git branch --show-current")[1]
  if not branch or branch == "" then
    vim.notify("Not on a branch", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  vim.api.nvim_buf_set_lines(0, row, row, false, { "Branch: `" .. branch .. "`", "" })
end

-- Insert git remote URL
function M.insert_remote()
  local remote = run_in_original_dir("git remote get-url origin")[1]
  if not remote or remote == "" then
    vim.notify("No remote origin", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  vim.api.nvim_buf_set_lines(0, row, row, false, { "Remote: " .. remote, "" })
end

-- Insert last commit details
function M.insert_last_commit()
  local commit = run_in_original_dir("git log -1 --pretty=format:'%h - %s (%an, %ar)'")[1]
  if not commit or commit == "" then
    vim.notify("No commits", vim.log.levels.INFO)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  vim.api.nvim_buf_set_lines(0, row, row, false, { "Last commit: " .. commit, "" })
end

-- Insert modified files list
function M.insert_modified_files()
  local files = run_in_original_dir "git diff --name-only"
  if #files == 0 or (files == 1 and files[1] == "") then
    vim.notify("No modified files", vim.log.levels.INFO)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]

  local lines = { "Modified files:", "" }
  for _, file in ipairs(files) do
    if file ~= "" then
      table.insert(lines, "- " .. file)
    end
  end
  table.insert(lines, "")

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)
end

-- Insert unstaged changes only
function M.insert_unstaged_changes()
  local diff = run_in_original_dir "git diff"
  if #diff == 0 or (diff == 1 and diff[1] == "") then
    vim.notify("No unstaged changes", vim.log.levels.INFO)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]

  local lines = { "Unstaged changes:", "", "```diff" }
  vim.list_extend(lines, diff)
  vim.list_extend(lines, { "```", "" })

  vim.api.nvim_buf_set_lines(0, row, row, false, lines)
end

-- Yank code with file path metadata (for clipboard-aware snippets)
function M.claude_yank()
  -- Get visual selection range
  local start_line = vim.fn.line "'<"
  local end_line = vim.fn.line "'>"

  -- Validate line numbers
  if start_line == 0 or end_line == 0 then
    vim.notify("Invalid visual selection", vim.log.levels.ERROR)
    return
  end

  -- Get file path from current buffer (NOT temp buffer)
  local file_path = vim.fn.expand "%:p"

  -- Validate we're not in a temp buffer
  if file_path:match "^/tmp/" then
    vim.notify("Cannot yank from temp buffer - yank from actual file", vim.log.levels.ERROR)
    return
  end

  -- Make path relative to git root
  local original_dir = vim.fn.environ().PWD or vim.fn.getcwd()
  local relative_path = vim.fn.system(
    string.format(
      "cd %s && realpath --relative-to=. %s 2>/dev/null",
      vim.fn.shellescape(original_dir),
      vim.fn.shellescape(file_path)
    )
  )
  file_path = vim.trim(relative_path)

  -- If realpath failed, use filename
  if file_path == "" or vim.v.shell_error ~= 0 then
    file_path = vim.fn.expand "%:."
  end

  -- Store metadata in global vars for snippets to use
  vim.g.claude_yank_file = file_path
  vim.g.claude_yank_start = start_line
  vim.g.claude_yank_end = end_line

  -- Yank to system clipboard
  vim.cmd 'normal! "+y'

  vim.notify(string.format("Yanked %s:%d-%d", file_path, start_line, end_line), vim.log.levels.INFO)
end

-- Register which-key mappings
function M.setup_which_key()
  local has_wk, wk = pcall(require, "which-key")
  if not has_wk then
    return
  end

  wk.add {
    { "<leader>c", group = "Claude Code" },
    { "<leader>cd", M.insert_git_diff, desc = "Insert git diff" },
    { "<leader>ci", M.insert_file_paths, desc = "Insert file paths (multi-select)" },
    { "<leader>cl", M.insert_git_log, desc = "Insert git log" },
    { "<leader>cy", M.claude_yank, desc = "Yank code with file path metadata", mode = "v" },
  }
end

-- Setup everything
function M.setup()
  if not M.is_claude_code_env() then
    return
  end

  M.setup_which_key()
end

return M
