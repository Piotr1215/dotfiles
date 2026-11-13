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

-- Where the reader's line `row` of `old` sits in `new`, after the text moved.
-- Anchors on the line's own text, or for a blank line on the nearest text
-- above it, and picks the copy of that text closest to where it was, so an
-- insertion above keeps the same paragraph under the cursor.
function M.relocate(old, row, new)
  local anchor = row
  while anchor > 1 and (old[anchor] or "") == "" do
    anchor = anchor - 1
  end
  local text, offset = old[anchor], row - anchor
  local best
  if text and text ~= "" then
    for i, line in ipairs(new) do
      if line == text and (not best or math.abs(i - anchor) < math.abs(best - anchor)) then
        best = i
      end
    end
  end
  local target = best and best + offset or row
  return math.max(1, math.min(target, #new))
end

return M
