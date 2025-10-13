local M = {}
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local previewers = require "telescope.previewers"
local utils = require "user_functions.utils"

-- Function to format reverted commits and their PRs
local function format_revert_summary(selections)
  local lines = {}
  local commits = {}
  local prs = {}
  local count = 0

  -- Collect commit and PR information
  for _, selection in ipairs(selections) do
    local commit = selection.value
    table.insert(commits, {
      hash = commit.hash,
      message = commit.message,
      pr = commit.pr_number,
    })
    if commit.pr_number then
      table.insert(prs, commit.pr_number)
    end
    count = count + 1
  end

  -- Format the summary
  table.insert(lines, string.format("Reverted %d commits:", count))
  table.insert(lines, "")

  -- Add commit information
  for _, commit in ipairs(commits) do
    table.insert(lines, string.format("Commit: %s", commit.hash))
    table.insert(lines, string.format("Message: %s", commit.message))
    if commit.pr then
      table.insert(lines, string.format("PR: #%s", commit.pr))
    end
    table.insert(lines, "")
  end

  -- Add PR summary if any exist
  if #prs > 0 then
    table.insert(lines, "Affected PRs:")
    for _, pr in ipairs(prs) do
      table.insert(lines, string.format("  #%s", pr))
    end
  end

  return lines
end

-- Function to show revert summary in floating window
local function show_revert_summary(selections)
  local content = format_revert_summary(selections)
  utils.create_floating_scratch(content)
end

-- Helper function to get commit diff
local function get_commit_diff(commit_hash, file_path)
  local cmd = string.format("git -C %s show %s -- %s", vim.fn.expand "%:p:h", commit_hash, file_path)
  local handle = io.popen(cmd)
  if not handle then
    return "Failed to get diff"
  end
  local diff = handle:read "*a"
  handle:close()
  return diff
end

-- Helper function to get PR details
local function get_pr_details(pr_number)
  if not pr_number then
    return ""
  end
  local cmd = string.format("gh pr view %s --json title,body,url 2>/dev/null", pr_number)
  local handle = io.popen(cmd)
  if not handle then
    return ""
  end
  local details = handle:read "*a"
  handle:close()
  if details == "" then
    return ""
  end
  local pr_info = vim.json.decode(details)
  if not pr_info then
    return ""
  end
  return string.format(
    "\nPR Details:\nTitle: %s\nURL: %s\n\nDescription:\n%s",
    pr_info.title or "",
    pr_info.url or "",
    pr_info.body or ""
  )
end

function M.get_recent_commits()
  local file_path = vim.fn.expand "%:p"
  local num_commits = 10
  local cmd = string.format("git -C %s log -n %d --oneline %s", vim.fn.expand "%:p:h", num_commits, file_path)
  local handle = io.popen(cmd)
  if not handle then
    return {}
  end
  local result = handle:read "*a"
  handle:close()
  local commits = vim.split(result, "\n")
  local formatted_commits = {}
  for _, commit in ipairs(commits) do
    if commit ~= "" then
      local hash, message = commit:match "(%w+)%s(.+)"
      local pr_number = message:match "#(%d+)"
      if hash then
        table.insert(formatted_commits, {
          hash = hash,
          message = message,
          pr_number = pr_number and pr_number or nil,
          display = pr_number and string.format("%s - %s (PR #%s)", hash, message, pr_number)
            or string.format("%s - %s", hash, message),
        })
      end
    end
  end
  return formatted_commits
end

-- Telescope picker for commit selection with preview
function M.show_and_revert()
  local commits = M.get_recent_commits()
  local file_path = vim.fn.expand "%:p"

  pickers
    .new({}, {
      prompt_title = "Git Commits",
      finder = finders.new_table {
        results = commits,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.display,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = previewers.new_buffer_previewer {
        title = "Commit Changes",
        define_preview = function(self, entry)
          local commit_diff = get_commit_diff(entry.value.hash, file_path)
          local pr_info = entry.value.pr_number and get_pr_details(entry.value.pr_number) or ""
          local content = commit_diff .. "\n" .. pr_info
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(content, "\n"))
          vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "diff")
        end,
      },
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local selections = picker:get_multi_selection()

          -- If no multi-selections, get current selection
          if vim.tbl_isempty(selections) then
            local entry = action_state.get_selected_entry()
            if entry then
              selections = { entry }
            end
          end

          actions.close(prompt_bufnr)

          if #selections > 0 then
            -- Sort selections by commit date (oldest first) to avoid conflicts
            table.sort(selections, function(a, b)
              return a.value.hash > b.value.hash
            end)

            -- First revert all commits
            for _, selection in ipairs(selections) do
              local cmd =
                string.format("git -C %s checkout %s^ -- %s", vim.fn.expand "%:p:h", selection.value.hash, file_path)
              local handle = io.popen(cmd)
              if handle then
                handle:close()
              end
            end

            -- Then show the summary
            show_revert_summary(selections)
          end
        end)

        -- Add proper multi-select mappings
        map("i", "<tab>", function(prompt_bufnr)
          actions.toggle_selection(prompt_bufnr)
          actions.move_selection_next(prompt_bufnr)
        end)
        map("n", "<tab>", function(prompt_bufnr)
          actions.toggle_selection(prompt_bufnr)
          actions.move_selection_next(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

-- Rest of your module functions (open_github_branch, open_github_pr, etc.)
local function get_git_info()
  local handle = io.popen "git rev-parse --abbrev-ref HEAD"
  if not handle then
    print "Failed to get branch name"
    return nil, nil
  end
  local branch = handle:read("*a"):gsub("%s+", "")
  handle:close()

  handle = io.popen "git config --get remote.origin.url"
  if not handle then
    print "Failed to get remote URL"
    return nil, nil
  end
  local remote_url = handle:read("*a"):gsub("%s+", "")
  handle:close()

  if remote_url:find "git@" then
    remote_url = remote_url:gsub(":", "/"):gsub("git@", "https://"):gsub("%.git$", "")
  elseif remote_url:find "https://" then
    remote_url = remote_url:gsub("%.git$", "")
  else
    print "Unsupported remote URL format"
    return nil, nil
  end

  return remote_url, branch
end

function M.open_github_branch()
  local remote_url, branch = get_git_info()
  if not remote_url or not branch then
    return
  end
  local url = remote_url .. "/tree/" .. branch
  os.execute("xdg-open " .. url)
end

function M.open_github_pr()
  local _, branch = get_git_info()
  if not branch then
    return
  end
  local handle = io.popen("gh pr list --head " .. branch .. " --json url --jq '.[0].url' 2>/dev/null")
  if not handle then
    print "Failed to get PR URL"
    return
  end
  local pr_url = handle:read("*a"):gsub("%s+", "")
  handle:close()

  if pr_url == "" then
    print "No open PR found for the current branch"
    return
  end
  os.execute("xdg-open " .. pr_url)
end

-- Command setup
vim.api.nvim_create_user_command("OpenGitHubBranch", function()
  M.open_github_branch()
end, {})

vim.api.nvim_create_user_command("OpenGitHubPR", function()
  M.open_github_pr()
end, {})

vim.api.nvim_create_user_command("RevertFileCommits", function()
  M.show_and_revert()
end, {})

-- Helper function to generate unique gist filename
local function generate_gist_filename()
  local current_file = vim.fn.expand "%:t"
  local timestamp = os.date "%Y%m%d_%H%M%S"

  if current_file and current_file ~= "" then
    local name, ext = current_file:match "^(.+)(%..+)$"
    if name and ext then
      return string.format("%s_%s%s", name, timestamp, ext)
    end
    return string.format("%s_%s", current_file, timestamp)
  end
  return string.format("gist_%s.md", timestamp)
end

-- Helper function to create gist and get URL
local function create_gist_and_get_url(content, filename)
  local tmp_file = string.format("/tmp/%s", filename)
  local file = io.open(tmp_file, "w")
  if not file then
    return nil, "Failed to create temporary file"
  end
  file:write(content)
  file:close()

  local cmd = string.format("gh gist create '%s' 2>&1", tmp_file)
  local handle = io.popen(cmd)
  if not handle then
    os.remove(tmp_file)
    return nil, "Failed to execute gh command"
  end

  local output = handle:read "*a"
  local exit_code = handle:close()
  os.remove(tmp_file)

  if not exit_code then
    return nil, "Failed to create gist: " .. output
  end

  local url = output:match "https://gist%.github%.com/%S+"
  if not url then
    return nil, "Gist created but failed to extract URL: " .. output
  end

  return url, nil
end

-- Create GitHub gist from current buffer or visual selection and copy URL to clipboard
function M.create_gist_from_buffer(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = (opts.line1 and opts.line2) and vim.api.nvim_buf_get_lines(bufnr, opts.line1 - 1, opts.line2, false)
    or vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local content = table.concat(lines, "\n")
  local filename = generate_gist_filename()
  local url, err = create_gist_and_get_url(content, filename)

  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  os.execute(string.format("echo -n '%s' | xclip -selection clipboard", url))
  vim.notify(string.format("Gist created! URL copied to clipboard:\n%s", url), vim.log.levels.INFO)
end

vim.api.nvim_create_user_command("CreateGist", function(opts)
  M.create_gist_from_buffer(opts)
end, { range = true })

-- Command abbreviations
vim.cmd "cabbrev ob OpenGitHubBranch"
vim.cmd "cabbrev opr OpenGitHubPR"
vim.cmd "cabbrev rcc RevertFileCommits"
vim.cmd "cabbrev cg CreateGist"

return M
