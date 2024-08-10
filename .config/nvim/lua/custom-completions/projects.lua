local source = {}

local function fetch_project_names()
  local path = vim.fn.expand "~/projects.txt" -- Path to the projects file
  local projects = {}
  for line in io.lines(path) do
    if line ~= "" then
      table.insert(projects, line)
    end
  end
  return projects
end

-- function source:is_available()
-- return true
-- end

-- function source:get_debug_name()
-- return "projects"
-- end

-- function source:get_keyword_pattern()
-- return [[\k\+]]
-- end

---Invoke completion (required).
---@param params cmp.SourceCompletionApiParams
---@param callback fun(response: lsp.CompletionResponse|nil)
function source:complete(params, callback)
  local project_names = fetch_project_names()
  local items = {}
  for _, name in ipairs(project_names) do
    table.insert(items, { label = name })
  end
  callback(items)
end

-- function source:resolve(completion_item, callback)
-- callback(completion_item)
-- end

-- function source:execute(completion_item, callback)
-- callback(completion_item)
-- end

require("cmp").register_source("projects", source)
