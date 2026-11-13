-- Follow what a markdown document points at: a Telescope picker over its
-- links, URLs and existing file paths. Enter opens a file in the window (like
-- gf) or a URL in the browser.
local M = {}

-- Collect what a reader can follow in `lines`: markdown link targets, bare
-- URLs, and file paths (link targets, `code` spans or path-like words) that
-- exist relative to `base_dir`. Returns { kind, target, lnum, text } entries,
-- one per distinct target, in document order.
function M.links(lines, base_dir)
  local out, seen, in_fence = {}, {}, false
  local function add(kind, target, lnum, text)
    if not seen[target] then
      seen[target] = true
      out[#out + 1] = { kind = kind, target = target, lnum = lnum, text = text }
    end
  end
  local function try_path(word, lnum, text)
    word = word:gsub("#.*$", ""):gsub("[.,;:]+$", "")
    if word == "" or word:find "[%$%s]" or word:match "^%a[%w+.-]*://" then
      return
    end
    local path = word:gsub("^~/", vim.env.HOME .. "/")
    if not path:match "^/" then
      path = vim.fs.normalize(base_dir .. "/" .. path)
    end
    if vim.uv.fs_stat(path) then
      add("file", path, lnum, text)
    end
  end
  for lnum, line in ipairs(lines) do
    if line:match "^%s*```" or line:match "^%s*~~~" then
      in_fence = not in_fence
    elseif not in_fence then
      local text = vim.trim(line)
      for url in line:gmatch "https?://[^%s%)%]>`\"']+" do
        add("url", (url:gsub("[.,;:]+$", "")), lnum, text)
      end
      for target in line:gmatch "%]%(([^%)%s]+)%)" do
        try_path(target, lnum, text)
      end
      for code in line:gmatch "`([^`]+)`" do
        try_path(code, lnum, text)
      end
      for word in line:gmatch "[%w._~/-]+" do
        if word:find "/" or word:match "%.%a%w*$" then
          try_path(word, lnum, text)
        end
      end
    end
  end
  return out
end

-- Directory that relative paths in the current buffer resolve against: the
-- source file's for a reading copy, else the buffer's own.
local function base_dir(buf)
  local src = vim.b[buf].markdown_reader_source
  local name = vim.api.nvim_buf_get_name(src and vim.api.nvim_buf_is_valid(src) and src or buf)
  return name ~= "" and vim.fn.fnamemodify(name, ":p:h") or vim.fn.getcwd()
end

-- Telescope picker over M.links of the current buffer. Enter opens a file in
-- this window (like gf) or a URL in the browser.
function M.pick_links()
  local buf = vim.api.nvim_get_current_buf()
  local entries = M.links(vim.api.nvim_buf_get_lines(buf, 0, -1, false), base_dir(buf))
  if #entries == 0 then
    vim.notify("no links or file paths here", vim.log.levels.INFO)
    return
  end
  local pickers, finders = require "telescope.pickers", require "telescope.finders"
  local conf, actions, state =
    require("telescope.config").values, require "telescope.actions", require "telescope.actions.state"
  local home = vim.env.HOME
  pickers
    .new({}, {
      prompt_title = "Links and files",
      finder = finders.new_table {
        results = entries,
        entry_maker = function(e)
          local shown = e.kind == "file" and e.target:gsub("^" .. vim.pesc(home), "~") or e.target
          local icon = e.kind == "url" and "󰖟 " or "󰈔 "
          return { value = e, display = icon .. shown, ordinal = e.kind .. " " .. shown .. " " .. e.text, lnum = e.lnum }
        end,
      },
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(prompt_bufnr)
          if not entry then
            return
          end
          if entry.value.kind == "url" then
            vim.ui.open(entry.value.target)
          else
            vim.cmd.edit(vim.fn.fnameescape(entry.value.target))
          end
        end)
        return true
      end,
    })
    :find()
end

return M
