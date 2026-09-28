-- Completion for ~/.claude/models.env: after `AGENT_MODEL_<ROLE>=` offer the
-- model ids that role accepts. The ids live in one place, __lib_models.sh,
-- reached through `__models.sh candidates <role>`, so a new model shipping never
-- touches this file. Enabled for that one buffer by the autocmd at the bottom,
-- not added to the global cmp sources, so no other buffer sees these items.

local M = {}

local models_cli = vim.fn.expand "~/.claude/scripts/__models.sh"

---Role name for a line such as `AGENT_MODEL_CLAUDE_ESCALATE=cl`, or nil.
---@param line string
---@return string|nil
function M.role_for_line(line)
  local var = line:match "^%s*AGENT_MODEL_([A-Z_]+)="
  if not var then
    return nil
  end
  return (var:lower():gsub("_", "-"))
end

---Ids for a role from the shell library. Empty when the role is unknown.
---@param role string
---@return string[]
function M.candidates(role)
  local out = vim.fn.systemlist { models_cli, "candidates", role }
  if vim.v.shell_error ~= 0 then
    return {}
  end
  return out
end

---Items for the text before the cursor. The current value sorts first so the
---model in use is never hidden behind the alternatives.
---@param before string
---@return table[]
function M.items_for_line(before)
  local role = M.role_for_line(before)
  if not role then
    return {}
  end
  local current = vim.fn.systemlist({ models_cli, "get", role })[1]
  local items = {}
  for i, id in ipairs(M.candidates(role)) do
    table.insert(items, {
      label = id,
      sortText = (id == current) and "0" or tostring(i),
      detail = (id == current) and "current" or nil,
    })
  end
  return items
end

local source = {}

function source:is_available()
  return vim.fn.expand "%:t" == "models.env"
end

function source:get_debug_name()
  return "models"
end

-- Ids contain hyphens and dots, which the default keyword pattern splits on.
function source:get_keyword_pattern()
  return [[\%([A-Za-z0-9._:-]\)\+]]
end

function source:get_trigger_characters()
  return { "=" }
end

---@param params table
---@param callback fun(response: table|nil)
function source:complete(params, callback)
  callback(M.items_for_line(params.context.cursor_before_line))
end

local ok, cmp = pcall(require, "cmp")
if ok then
  cmp.register_source("models", source)

  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    group = vim.api.nvim_create_augroup("ModelsEnvCompletion", { clear = true }),
    pattern = "models.env",
    callback = function(args)
      vim.bo[args.buf].filetype = "sh"
      cmp.setup.buffer { sources = { { name = "models" } } }
    end,
  })
end

return M
