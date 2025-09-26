local M = {}

local function parse_alignment(header_sep)
  local alignment = {}
  for part in header_sep:gmatch "[^|]+" do
    local trimmed = part:match "^%s*(.-)%s*$"
    if trimmed:match "^:%-+:$" then
      table.insert(alignment, "center")
    elseif trimmed:match "^:%-+$" then
      table.insert(alignment, "left")
    elseif trimmed:match "^%-+:$" then
      table.insert(alignment, "right")
    else
      table.insert(alignment, "left")
    end
  end
  return alignment
end

local function split_table_row(line)
  local cells = {}
  for cell in line:gmatch "[^|]+" do
    local trimmed = cell:match "^%s*(.-)%s*$" or ""
    table.insert(cells, trimmed)
  end
  return cells
end

local function is_separator_line(line)
  return line:match "^%s*|?%s*:?%-+:?%s*|" ~= nil
end

local function format_separator(alignment, widths)
  local parts = {}
  for i, align in ipairs(alignment) do
    local width = widths[i] or 3
    local sep
    if align == "center" then
      sep = ":" .. string.rep("-", math.max(1, width - 2)) .. ":"
    elseif align == "right" then
      sep = string.rep("-", math.max(1, width - 1)) .. ":"
    else
      sep = string.rep("-", width)
    end
    table.insert(parts, sep)
  end
  return "| " .. table.concat(parts, " | ") .. " |"
end

local function format_row(cells, widths, alignment)
  local formatted = {}
  for i, cell in ipairs(cells) do
    local width = widths[i] or 3
    local align = alignment[i] or "left"
    local padding = width - vim.fn.strwidth(cell)

    if padding > 0 then
      if align == "center" then
        local left_pad = math.floor(padding / 2)
        local right_pad = padding - left_pad
        cell = string.rep(" ", left_pad) .. cell .. string.rep(" ", right_pad)
      elseif align == "right" then
        cell = string.rep(" ", padding) .. cell
      else
        cell = cell .. string.rep(" ", padding)
      end
    end
    table.insert(formatted, cell)
  end
  return "| " .. table.concat(formatted, " | ") .. " |"
end

function M.format_table()
  local mode = vim.api.nvim_get_mode().mode
  local start_line, end_line

  if mode:match "^[vV]" then
    start_line = vim.fn.line "'<"
    end_line = vim.fn.line "'>"
    vim.cmd "normal! "
  else
    local cur_line = vim.fn.line "."
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    start_line = cur_line
    for i = cur_line - 1, 1, -1 do
      if lines[i]:match "^%s*|" then
        start_line = i
      else
        break
      end
    end

    end_line = cur_line
    for i = cur_line, #lines do
      if lines[i]:match "^%s*|" then
        end_line = i
      else
        break
      end
    end
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  local table_data = {}
  local alignment = {}
  local max_cols = 0
  local separator_idx = -1

  for i, line in ipairs(lines) do
    if is_separator_line(line) then
      alignment = parse_alignment(line)
      separator_idx = i
    else
      local cells = split_table_row(line)
      table.insert(table_data, cells)
      max_cols = math.max(max_cols, #cells)
    end
  end

  if #table_data == 0 then
    vim.notify("No table found to format", vim.log.levels.WARN)
    return
  end

  if #alignment == 0 then
    for i = 1, max_cols do
      alignment[i] = "left"
    end
  end

  for _, row in ipairs(table_data) do
    for i = #row + 1, max_cols do
      row[i] = ""
    end
  end

  local widths = {}
  for i = 1, max_cols do
    widths[i] = 3
    for _, row in ipairs(table_data) do
      if row[i] then
        widths[i] = math.max(widths[i], vim.fn.strwidth(row[i]))
      end
    end
  end

  local formatted = {}
  local data_idx = 1
  for i = 1, #lines do
    if i == separator_idx then
      table.insert(formatted, format_separator(alignment, widths))
    else
      if table_data[data_idx] then
        table.insert(formatted, format_row(table_data[data_idx], widths, alignment))
        data_idx = data_idx + 1
      end
    end
  end

  if separator_idx == -1 and #formatted >= 1 then
    table.insert(formatted, 2, format_separator(alignment, widths))
  end

  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, formatted)
  vim.notify("Table formatted successfully", vim.log.levels.INFO)
end

function M.insert_table(rows, cols)
  rows = rows or 3
  cols = cols or 3

  local lines = {}

  local header = {}
  for i = 1, cols do
    table.insert(header, "Header " .. i)
  end
  table.insert(lines, "| " .. table.concat(header, " | ") .. " |")

  local separator = {}
  for i = 1, cols do
    table.insert(separator, "---")
  end
  table.insert(lines, "| " .. table.concat(separator, " | ") .. " |")

  for r = 1, rows - 1 do
    local row = {}
    for c = 1, cols do
      table.insert(row, "Cell " .. r .. "," .. c)
    end
    table.insert(lines, "| " .. table.concat(row, " | ") .. " |")
  end

  local cur_line = vim.fn.line "."
  vim.api.nvim_buf_set_lines(0, cur_line, cur_line, false, lines)
end

return M
