-- Completion for .envrc: typing `pass` at the start of a line offers every
-- password-store entry, and picking one writes the direnv line
-- `_pass_export NAME entry` (see .config/direnv/pass-export.sh).
-- Only entry names are read, from the .gpg filenames; nothing is decrypted.
-- Listed in the global cmp sources, gated to .envrc by is_available.

local M = {}

---Password-store entries, e.g. `personal/MULLAVAD_PRIVATE_KEY`, sorted.
---@return string[]
function M.entries()
  local store = vim.env.PASSWORD_STORE_DIR or vim.fn.expand "~/.password-store"
  local entries = {}
  if vim.fn.isdirectory(store) == 0 then
    return entries
  end
  local walk = vim.fs.dir(store, {
    depth = math.huge,
    skip = function(dir)
      return vim.fs.basename(dir):sub(1, 1) ~= "."
    end,
  })
  for name, kind in walk do
    if kind == "file" and name:sub(-4) == ".gpg" then
      table.insert(entries, name:sub(1, -5))
    end
  end
  table.sort(entries)
  return entries
end

---Shell variable name for an entry: its basename, case kept (TF_VAR_ names
---are case-sensitive), anything outside [A-Za-z0-9_] turned into `_`.
---@param entry string
---@return string
function M.var_name(entry)
  local name = vim.fs.basename(entry):gsub("[^%w_]", "_")
  if name:match "^%d" then
    name = "_" .. name
  end
  return name
end

---The `_pass_export` line for an entry.
---@param entry string
---@return string
function M.export_line(entry)
  return ("_pass_export %s %s"):format(M.var_name(entry), entry)
end

---Completion items for the text before the cursor; empty unless the line so
---far is `pass` plus an optional filter.
---@param before string
---@return table[]
function M.items_for_line(before)
  if not before:match "^%s*pass[%w_/%.@%-]*$" then
    return {}
  end
  local items = {}
  for _, entry in ipairs(M.entries()) do
    table.insert(items, {
      label = entry,
      filterText = "pass" .. entry,
      insertText = M.export_line(entry),
      detail = M.export_line(entry),
    })
  end
  return items
end

local source = {}

function source:is_available()
  return vim.fn.expand "%:t" == ".envrc"
end

function source:get_debug_name()
  return "pass"
end

-- Covers the whole `pass<filter>` run so the pick replaces it, and so the
-- source stays silent until `pass` is typed.
function source:get_keyword_pattern()
  return [[pass[0-9A-Za-z_/.@-]*]]
end

---@param params table
---@param callback fun(response: table|nil)
function source:complete(params, callback)
  callback(M.items_for_line(params.context.cursor_before_line))
end

local ok, cmp = pcall(require, "cmp")
if ok then
  cmp.register_source("pass", source)
end

return M
