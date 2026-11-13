-- Follow what a markdown document points at. <leader>mo is a Telescope picker
-- over its links, URLs, file paths and same-page anchors; <leader>mh is an
-- outline of its headings; <CR> in reading mode follows the link under the
-- cursor. A URL opens in the browser, a file opens in the window (a markdown
-- file in reading mode), and a #heading anchor jumps to that heading. Every
-- jump goes through the jumplist, so <C-o> returns to where you were.
local M = {}

local function fence(line)
  return line:match "^%s*```" or line:match "^%s*~~~"
end

-- GitHub-style anchor for a heading text: lower case, punctuation dropped,
-- spaces to dashes.
function M.slug(text)
  return (text:lower():gsub("[^%w%s_-]", ""):gsub("%s", "-"))
end

-- Headings of `lines` outside fenced code, as { lnum, level, text, slug }.
function M.headings(lines)
  local out, in_fence = {}, false
  for lnum, line in ipairs(lines) do
    if fence(line) then
      in_fence = not in_fence
    elseif not in_fence then
      local hashes, text = line:match "^(#+)%s+(.-)%s*#*%s*$"
      if hashes and #hashes <= 6 then
        out[#out + 1] = { lnum = lnum, level = #hashes, text = text, slug = M.slug(text) }
      end
    end
  end
  return out
end

-- What `raw` points at, resolved against `base_dir`: { kind = "url" }, a
-- same-page { kind = "heading", anchor }, or an existing { kind = "file",
-- target, anchor }. Nil when it points at nothing that exists.
function M.resolve(raw, base_dir)
  raw = raw:gsub("[.,;:]+$", "")
  if raw:match "^https?://" then
    return { kind = "url", target = raw }
  end
  if raw:match "^#" and #raw > 1 then
    return { kind = "heading", target = raw, anchor = raw:sub(2) }
  end
  local path, anchor = raw:match "^([^#]*)#?(.*)$"
  if path == "" or path:find "[%$%s]" or path:match "^%a[%w+.-]*://" then
    return nil
  end
  path = path:gsub("^~/", vim.env.HOME .. "/")
  if not path:match "^/" then
    path = vim.fs.normalize(base_dir .. "/" .. path)
  end
  if not vim.uv.fs_stat(path) then
    return nil
  end
  return { kind = "file", target = path, anchor = anchor ~= "" and anchor or nil }
end

-- Spans on `line` a reader can follow, as { from, to, raw } with 1-based byte
-- columns: markdown links, bare URLs, `code` spans and path-like words.
local function spans(line)
  local out = {}
  local function each(pattern, pick)
    local pos = 1
    while true do
      local s, e, a = line:find(pattern, pos)
      if not s then
        break
      end
      out[#out + 1] = { from = s, to = e, raw = pick and a or line:sub(s, e) }
      pos = e + 1
    end
  end
  each("%[[^%]]*%]%(([^%)%s]+)%)", true)
  each "https?://[^%s%)%]>`\"']+"
  each("`([^`]+)`", true)
  each "[%w._~/#-]+"
  return out
end

-- Everything followable in `lines`, one entry per distinct target in document
-- order: { kind, target, anchor, lnum, text }. Fenced code is skipped; a bare
-- word only counts when it names an existing file.
function M.links(lines, base_dir)
  local out, seen, in_fence = {}, {}, false
  for lnum, line in ipairs(lines) do
    if fence(line) then
      in_fence = not in_fence
    elseif not in_fence then
      for _, span in ipairs(spans(line)) do
        local raw = span.raw
        local wordish = not raw:find "^%#" and (raw:find "/" or raw:match "%.%a%w*$" or raw:match "^https?://")
        local is_link = line:sub(span.from, span.from) == "[" or line:sub(span.from, span.from) == "`"
        if is_link or wordish or raw:match "^https?://" then
          local hit = M.resolve(raw, base_dir)
          if hit and not (hit.kind == "heading" and not is_link) then
            local key = hit.target .. "#" .. (hit.anchor or "")
            if not seen[key] then
              seen[key] = true
              hit.lnum, hit.text = lnum, vim.trim(line)
              out[#out + 1] = hit
            end
          end
        end
      end
    end
  end
  return out
end

-- The followable target under byte column `col` (1-based) of `line`, or nil.
-- The innermost span wins, so a URL inside a markdown link resolves once.
function M.target_at(line, col, base_dir)
  local best
  for _, span in ipairs(spans(line)) do
    if span.from <= col and col <= span.to then
      local hit = M.resolve(span.raw, base_dir)
      if hit and (not best or span.from >= best.from) then
        best = { from = span.from, hit = hit }
      end
    end
  end
  return best and best.hit
end

-- Directory that relative paths in `buf` resolve against.
local function base_dir(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and vim.fn.fnamemodify(name, ":p:h") or vim.fn.getcwd()
end

-- Move the cursor to the heading whose anchor is `anchor` in the current
-- buffer. `remember` records the jump first, so <C-o> comes back; a jump
-- right after opening a file skips that, since the open already recorded it.
-- Returns whether a heading was found.
local function jump_to_anchor(anchor, remember)
  local wanted = M.slug(anchor)
  for _, h in ipairs(M.headings(vim.api.nvim_buf_get_lines(0, 0, -1, false))) do
    if h.slug == wanted then
      if remember then
        vim.cmd "normal! m'"
      end
      vim.api.nvim_win_set_cursor(0, { h.lnum, 0 })
      vim.cmd "normal! zt"
      return true
    end
  end
  vim.notify("no heading #" .. anchor, vim.log.levels.WARN)
  return false
end

-- Open what `hit` points at. A markdown file opened from reading mode opens
-- in reading mode too.
function M.open(hit)
  if hit.kind == "url" then
    vim.ui.open(hit.target)
    return
  end
  if hit.kind == "heading" then
    jump_to_anchor(hit.anchor, true)
    return
  end
  local reader = require "markdown_reader"
  local reading = reader.is_reading()
  vim.cmd.edit(vim.fn.fnameescape(hit.target))
  if reading and hit.target:match "%.md$" then
    reader.enter()
  end
  if hit.anchor then
    jump_to_anchor(hit.anchor, false)
  end
end

-- Follow the link under the cursor; fall back to gf when nothing resolves.
function M.follow()
  local buf = vim.api.nvim_get_current_buf()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local hit = M.target_at(vim.api.nvim_get_current_line(), col, base_dir(buf))
  if hit then
    M.open(hit)
  else
    pcall(vim.cmd, "normal! gf")
  end
end

local function picker(title, entries, make, on_pick)
  local pickers, finders = require "telescope.pickers", require "telescope.finders"
  local conf, actions, state =
    require("telescope.config").values, require "telescope.actions", require "telescope.actions.state"
  pickers
    .new({}, {
      prompt_title = title,
      finder = finders.new_table { results = entries, entry_maker = make },
      sorter = conf.generic_sorter {},
      previewer = conf.grep_previewer {},
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            on_pick(entry.value)
          end
        end)
        return true
      end,
    })
    :find()
end

-- Telescope picker over M.links of the current buffer, with a preview: a file
-- shows itself, a URL or anchor shows the document at its line.
function M.pick_links()
  local buf = vim.api.nvim_get_current_buf()
  local entries = M.links(vim.api.nvim_buf_get_lines(buf, 0, -1, false), base_dir(buf))
  if #entries == 0 then
    vim.notify("no links or file paths here", vim.log.levels.INFO)
    return
  end
  local doc = vim.api.nvim_buf_get_name(buf)
  local home, icons = vim.env.HOME, { url = "󰖟 ", file = "󰈔 ", heading = "󰓩 " }
  picker("Links and files", entries, function(e)
    local shown = e.kind == "file" and e.target:gsub("^" .. vim.pesc(home), "~") or e.target
    if e.kind == "file" and e.anchor then
      shown = shown .. "#" .. e.anchor
    end
    local is_file = e.kind == "file"
    return {
      value = e,
      display = icons[e.kind] .. shown,
      ordinal = e.kind .. " " .. shown .. " " .. e.text,
      path = is_file and e.target or doc,
      lnum = not is_file and e.lnum or nil,
    }
  end, M.open)
end

-- Telescope outline of the current buffer's headings, indented by level.
-- Enter jumps there through the jumplist.
function M.pick_headings()
  local buf = vim.api.nvim_get_current_buf()
  local entries = M.headings(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if #entries == 0 then
    vim.notify("no headings here", vim.log.levels.INFO)
    return
  end
  local doc = vim.api.nvim_buf_get_name(buf)
  picker("Outline", entries, function(h)
    return {
      value = h,
      display = string.rep("  ", h.level - 1) .. h.text,
      ordinal = h.text,
      path = doc,
      lnum = h.lnum,
    }
  end, function(h)
    vim.cmd "normal! m'"
    vim.api.nvim_win_set_cursor(0, { h.lnum, 0 })
    vim.cmd "normal! zt"
  end)
end

return M
