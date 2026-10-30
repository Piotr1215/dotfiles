-- Completion for ~/.claude/models.env: after `AGENT_MODEL_<ROLE>=` offer the
-- live provider model ids from `__models.sh candidates <role>`. Enabled for
-- that one buffer by the autocmd at the bottom,
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

---Fetch completion items without blocking the editor.
---@param before string
---@param callback fun(items: table[])
function M.items_for_line(before, callback)
  local role = M.role_for_line(before)
  if not role then
    callback {}
    return
  end
  local function run(args, done)
    local ok, err = pcall(vim.system, args, { text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          vim.notify("Model completion failed: " .. vim.trim(result.stderr or ""), vim.log.levels.WARN)
          callback {}
        else
          done(result.stdout or "")
        end
      end)
    end)
    if not ok then
      vim.schedule(function()
        vim.notify("Model completion failed: " .. tostring(err), vim.log.levels.WARN)
        callback {}
      end)
    end
  end
  run({ models_cli, "candidates", role }, function(output)
    run({ models_cli, "get", role }, function(value)
      local current = vim.trim(value)
      local items = {}
      for i, id in ipairs(vim.split(output, "\n", { trimempty = true })) do
        table.insert(items, {
          label = id,
          sortText = (id == current) and "0" or tostring(i),
          detail = (id == current) and "current" or nil,
        })
      end
      callback(items)
    end)
  end)
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
  M.items_for_line(params.context.cursor_before_line, callback)
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
