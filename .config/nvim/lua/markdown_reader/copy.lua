-- Reading copy text: a blank line between list items, so dense lists breathe
-- and } steps item by item. Fenced code is left as is.
local M = {}

local function is_list_item(line)
  return line:match "^%s*[-*+]%s" or line:match "^%s*%d+[.)]%s"
end

-- Build the reading copy of `lines`. Returns the new lines and a map from each
-- source line number to its line number in the copy.
function M.spaced_lines(lines)
  local out, map, in_fence = {}, {}, false
  for i, line in ipairs(lines) do
    if line:match "^%s*```" or line:match "^%s*~~~" then
      in_fence = not in_fence
    end
    out[#out + 1] = line
    map[i] = #out
    local next_line = lines[i + 1]
    if not in_fence and next_line and is_list_item(line) and is_list_item(next_line) then
      out[#out + 1] = ""
    end
  end
  return out, map
end

return M
