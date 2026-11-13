-- Paragraphs in reading mode. Consecutive list items get a visual-only gap
-- between them (no text is added to the file), and the paragraph motions and
-- text objects treat that gap like a blank line, so } steps item by item and
-- yip yanks one item. Fenced code is left as is.
local M = {}

local function is_list_item(line)
  return line:match "^%s*[-*+]%s" or line:match "^%s*%d+[.)]%s"
end

local function is_fence(line)
  return line:match "^%s*```" or line:match "^%s*~~~"
end

-- Rows of `lines` that get a gap below them: a list item followed directly by
-- another, outside fenced code. Returned as a set, row -> true.
function M.gaps(lines)
  local out, in_fence = {}, false
  for i, line in ipairs(lines) do
    if is_fence(line) then
      in_fence = not in_fence
    end
    local next_line = lines[i + 1]
    if not in_fence and next_line and is_list_item(line) and is_list_item(next_line) then
      out[i] = true
    end
  end
  return out
end

-- Row a paragraph motion from `row` lands on, `forward` for } and not for {.
-- Like the built-in motions it stops on the empty line next to a paragraph;
-- at a gap it stops on the item below the gap, the line the gap belongs to.
-- Runs to the first or last line when nothing is left.
function M.stop(lines, gaps, row, forward)
  local last = #lines
  local function empty(r)
    return lines[r] == ""
  end
  local function lands(r)
    if forward then
      return (empty(r) and r > 1 and not empty(r - 1)) or gaps[r - 1]
    end
    return (empty(r) and r < last and not empty(r + 1)) or gaps[r - 1]
  end
  local step, r = forward and 1 or -1, row + (forward and 1 or -1)
  while r >= 1 and r <= last do
    if lands(r) then
      return r
    end
    r = r + step
  end
  return forward and last or 1
end

-- First and last row of the paragraph at `row`: the run of non-empty lines
-- around it, cut at gaps. On an empty line, the run of empty lines. `around`
-- adds the empty lines after the paragraph, or before it when none follow;
-- a paragraph that ends at a gap has none to add.
function M.paragraph(lines, gaps, row, around)
  local function empty(r)
    return lines[r] == ""
  end
  local first, last = row, row
  if empty(row) then
    while first > 1 and empty(first - 1) do
      first = first - 1
    end
    while last < #lines and empty(last + 1) do
      last = last + 1
    end
    return first, last
  end
  while first > 1 and not empty(first - 1) and not gaps[first - 1] do
    first = first - 1
  end
  while last < #lines and not empty(last + 1) and not gaps[last] do
    last = last + 1
  end
  if around and not gaps[last] then
    local after = last
    while after < #lines and empty(after + 1) do
      after = after + 1
    end
    if after > last then
      return first, after
    end
    while first > 1 and empty(first - 1) do
      first = first - 1
    end
  end
  return first, last
end

return M
