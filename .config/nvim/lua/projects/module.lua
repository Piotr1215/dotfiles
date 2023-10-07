local source = {}

---Return whether this source is available in the current context or not (optional).
---@return boolean
function source:is_available()
  return true
end

-- Option defaults
local option_defaults = {
  cache_projects_on_start = true,
}
---Return the debug name of this source (optional).
---@return string
function source:get_debug_name()
  return 'projects'
end

-- Constructor
function source.new()
  local self = setmetatable({}, { __index = source })
  self._cached_items = nil
  return self
end

---Return the keyword pattern for triggering completion (optional).
---If this is ommited, nvim-cmp will use a default keyword pattern. See |cmp-config.completion.keyword_pattern|.
---@return string
function source:get_keyword_pattern()
  return [[\k\+]]
end

-- Function to get Taskwarrior projects
local function get_taskwarrior_projects()
  local handle = io.popen("task projects")
  local result = handle:read("*a")
  handle:close()

  local projects = {}
  for line in result:gmatch("[^\r\n]+") do
    local project, tasks = line:match("([%w%-]+)%s+(%d+)")
    if project and tasks then
      table.insert(projects, project)
    end
  end

  print("Debug: Final projects list before returning:")
  print(vim.inspect(projects))

  return projects
end

---Invoke completion (required).
---@param params cmp.SourceCompletionApiParams
---@param callback fun(response: lsp.CompletionResponse|nil)
function source:complete(params, callback)
  local opts = vim.tbl_deep_extend('keep', params.option, option_defaults)

  local items
  if opts.cache_projects_on_start then
    if self._cached_items == nil then
      self._cached_items = get_taskwarrior_projects()
    end
    items = vim.deepcopy(self._cached_items)
  else
    items = get_taskwarrior_projects()
  end

  local completion_items = {}
  for _, project in ipairs(items) do
    table.insert(completion_items, { label = project, insertText = project })
  end

  callback({ items = completion_items })
end

---Resolve completion item (optional). This is called right before the completion is about to be displayed.
---Useful for setting the text shown in the documentation window (`completion_item.documentation`).
---@param completion_item lsp.CompletionItem
---@param callback fun(completion_item: lsp.CompletionItem|nil)
function source:resolve(completion_item, callback)
  callback(completion_item)
end

---Executed after the item was selected.
---@param completion_item lsp.CompletionItem
---@param callback fun(completion_item: lsp.CompletionItem|nil)
function source:execute(completion_item, callback)
  callback(completion_item)
end

---Register your source to nvim-cmp.
require('cmp').register_source('projects', source)
