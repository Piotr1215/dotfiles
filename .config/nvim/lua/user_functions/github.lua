local M = {}

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

vim.api.nvim_create_user_command("OpenGitHubBranch", function()
  M.open_github_branch()
end, {})

vim.api.nvim_create_user_command("OpenGitHubPR", function()
  M.open_github_pr()
end, {})

vim.cmd "cabbrev op OpenGitHubBranch"
vim.cmd "cabbrev opr OpenGitHubPR"

return M
