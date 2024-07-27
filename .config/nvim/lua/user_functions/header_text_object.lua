-- ~/.config/nvim/lua/user_functions/header_text_object.lua
local M = {}

function M.select_header(outer, count)
  count = count or 1
  local last_line = vim.fn.line "$"
  local start_line, end_line

  for i = 1, count do
    -- Find the start of the current/next header
    local header_start = vim.fn.search("^#\\+\\s", i == 1 and "bcW" or "W")
    if header_start == 0 or header_start > last_line then
      break
    end

    -- Set the start line on the first iteration
    if i == 1 then
      start_line = header_start + (outer and 0 or 1)
    end

    -- Find the end of the current header
    end_line = vim.fn.search("^#\\+\\s", "nW") - 1
    if end_line < header_start then
      end_line = last_line
    end

    -- Stop if we've reached the end of the file
    if end_line == last_line then
      break
    end
  end

  -- Perform the selection
  vim.fn.cursor(start_line, 1)
  vim.cmd "normal! V"
  vim.fn.cursor(end_line, 1)
end

for _, mapping in ipairs {
  { "o", "ih" },
  { "o", "ah" },
  { "x", "ih" },
  { "x", "ah" },
} do
  vim.keymap.set(mapping[1], mapping[2], function()
    M.select_header(mapping[2] == "ah", vim.v.count1)
  end, { silent = true })
end

return M
