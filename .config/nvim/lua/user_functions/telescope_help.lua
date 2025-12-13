-- Telescope pickers for tldr and cheat.sh
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local previewers = require "telescope.previewers"

local M = {}

-- Get list of tldr pages from cache
local function get_tldr_pages()
  local pages = {}
  local tldr_dir = vim.fn.expand "~/.local/share/tldr/tldr/pages"
  local dirs = { tldr_dir .. "/common", tldr_dir .. "/linux" }

  for _, dir in ipairs(dirs) do
    local handle = io.popen("find " .. dir .. " -name '*.md' 2>/dev/null")
    if handle then
      for line in handle:lines() do
        local name = line:match "([^/]+)%.md$"
        if name and not pages[name] then
          pages[name] = true
        end
      end
      handle:close()
    end
  end

  local result = {}
  for name in pairs(pages) do
    table.insert(result, name)
  end
  table.sort(result)
  return result
end

-- tldr telescope picker
M.tldr = function(opts)
  opts = opts or {}
  pickers
    .new(opts, {
      prompt_title = "tldr",
      finder = finders.new_table {
        results = get_tldr_pages(),
      },
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_termopen_previewer {
        get_command = function(entry)
          return { "tldr", entry.value }
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            vim.cmd("Tldr " .. selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

-- Cache for cheat.sh topics
local cheat_cache = nil

local function get_cheat_topics()
  if cheat_cache then
    return cheat_cache
  end
  local handle = io.popen "curl -s 'cht.sh/:list' 2>/dev/null"
  if handle then
    local result = {}
    for line in handle:lines() do
      if line ~= "" and not line:match "^:" then
        table.insert(result, line)
      end
    end
    handle:close()
    cheat_cache = result
    return result
  end
  return {}
end

-- cheat.sh telescope picker
M.cheat = function(opts)
  opts = opts or {}
  pickers
    .new(opts, {
      prompt_title = "cheat.sh",
      finder = finders.new_table {
        results = get_cheat_topics(),
      },
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_termopen_previewer {
        get_command = function(entry)
          -- URL-encode special chars
          local encoded = entry.value:gsub("([^%w%-_%.~])", function(c)
            return string.format("%%%02X", string.byte(c))
          end)
          return { "curl", "-s", "cht.sh/" .. encoded }
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            vim.cmd("Cheat " .. selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

-- Cache for shellcheck codes with descriptions
local sc_cache = nil
local sc_cache_file = vim.fn.stdpath "cache" .. "/shellcheck_codes.txt"
local sc_preview_cache = {} -- Cache previews in memory

local function get_sc_codes()
  if sc_cache then
    return sc_cache
  end

  -- Try loading from cache file first
  local f = io.open(sc_cache_file, "r")
  if f then
    local result = {}
    for line in f:lines() do
      local code, desc = line:match "^(SC%d+): (.+)$"
      if code then
        table.insert(result, { code = code, desc = desc })
      end
    end
    f:close()
    if #result > 0 then
      sc_cache = result
      return result
    end
  end

  -- Fetch codes from wiki
  vim.notify("Fetching shellcheck codes (first time only)...", vim.log.levels.INFO)
  local handle = io.popen "curl -s 'https://www.shellcheck.net/wiki/' 2>/dev/null | grep -oP 'SC\\d{4}' | sort -u"
  if not handle then
    return {}
  end

  local codes = {}
  for line in handle:lines() do
    table.insert(codes, line)
  end
  handle:close()

  -- Fetch descriptions one by one (simpler, more reliable)
  local result = {}
  for _, code in ipairs(codes) do
    local cmd = "curl -s 'https://www.shellcheck.net/wiki/" .. code .. "' | grep '<title>' | sed 's/.*– //;s/<.*//'"
    local desc_handle = io.popen(cmd)
    if desc_handle then
      local desc = desc_handle:read "*l" or ""
      desc_handle:close()
      desc = desc:gsub("^%s+", ""):gsub("%s+$", "")
      if desc ~= "" then
        table.insert(result, { code = code, desc = desc })
      end
    end
  end

  -- Save to cache file
  f = io.open(sc_cache_file, "w")
  if f then
    for _, item in ipairs(result) do
      f:write(item.code .. ": " .. item.desc .. "\n")
    end
    f:close()
  end

  sc_cache = result
  return result
end

-- Shellcheck wiki picker
M.shellcheck = function(opts)
  opts = opts or {}
  pickers
    .new(opts, {
      prompt_title = "Shellcheck Wiki",
      finder = finders.new_table {
        results = get_sc_codes(),
        entry_maker = function(entry)
          return {
            value = entry.code,
            display = entry.code .. " - " .. entry.desc,
            ordinal = entry.code .. " " .. entry.desc,
          }
        end,
      },
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer {
        title = "Shellcheck Explanation",
        define_preview = function(self, entry)
          local bufnr = self.state.bufnr
          local code = entry.value

          -- Use cached preview if available
          if sc_preview_cache[code] then
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, sc_preview_cache[code])
            vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
            return
          end

          -- Show loading message
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Loading..." })

          -- Fetch async
          local url = "https://www.shellcheck.net/wiki/" .. code
          local cmd = "curl -sL '" .. url .. "' | pandoc -f html -t markdown 2>/dev/null"
          vim.fn.jobstart(cmd, {
            stdout_buffered = true,
            on_stdout = function(_, data)
              if data and vim.api.nvim_buf_is_valid(bufnr) then
                sc_preview_cache[code] = data
                vim.schedule(function()
                  if vim.api.nvim_buf_is_valid(bufnr) then
                    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, data)
                    vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
                  end
                end)
              end
            end,
          })
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            vim.cmd("SC " .. selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

-- Pure Bash Bible picker
local bash_bible_path = vim.fn.expand "~/dev/pure-bash-bible/README.md"
local bash_bible_cache = nil

local function get_bash_bible_sections()
  if bash_bible_cache then
    return bash_bible_cache
  end

  local f = io.open(bash_bible_path, "r")
  if not f then
    vim.notify("pure-bash-bible not found at " .. bash_bible_path, vim.log.levels.ERROR)
    return {}
  end

  local result = {}
  local line_num = 0
  local current_section = nil

  for line in f:lines() do
    line_num = line_num + 1
    -- Match main sections (# HEADING)
    local main = line:match "^# ([A-Z][A-Z ]+)$"
    if main then
      current_section = main
      table.insert(result, {
        heading = main,
        line = line_num,
        level = 1,
        section = main,
      })
    end
    -- Match subsections (## Heading)
    local sub = line:match "^## (.+)$"
    if sub then
      table.insert(result, {
        heading = sub,
        line = line_num,
        level = 2,
        section = current_section,
      })
    end
  end
  f:close()

  bash_bible_cache = result
  return result
end

-- Get content from line to next heading of same or higher level
local function get_section_content(start_line, level)
  local f = io.open(bash_bible_path, "r")
  if not f then
    return {}
  end

  local result = {}
  local line_num = 0
  local collecting = false
  -- For level 1 (# HEADING), stop at next level 1
  -- For level 2 (## Heading), stop at next level 1 or 2
  local stop_pattern = level == 1 and "^# [A-Z]" or "^##? "

  for line in f:lines() do
    line_num = line_num + 1
    if line_num == start_line then
      collecting = true
    elseif collecting and line:match(stop_pattern) then
      break
    end
    if collecting then
      table.insert(result, line)
    end
  end
  f:close()
  return result
end

M.bash_bible = function(opts)
  opts = opts or {}
  pickers
    .new(opts, {
      prompt_title = "Pure Bash Bible",
      finder = finders.new_table {
        results = get_bash_bible_sections(),
        entry_maker = function(entry)
          local prefix = entry.level == 1 and "# " or "  "
          return {
            value = entry,
            display = prefix .. entry.heading,
            ordinal = entry.heading .. " " .. (entry.section or ""),
          }
        end,
      },
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer {
        title = "Bash Bible",
        define_preview = function(self, entry)
          local bufnr = self.state.bufnr
          local content = get_section_content(entry.value.line, entry.value.level)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
          vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            -- Read full file
            local f = io.open(bash_bible_path, "r")
            if not f then
              return
            end
            local lines = {}
            for line in f:lines() do
              table.insert(lines, line)
            end
            f:close()
            -- Open in scratch buffer
            vim.cmd "new"
            vim.bo.buftype = "nofile"
            vim.bo.bufhidden = "wipe"
            vim.bo.swapfile = false
            vim.bo.filetype = "markdown"
            vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
            vim.api.nvim_buf_set_keymap(0, "n", "q", ":q!<CR>", { noremap = true, silent = true })
            vim.api.nvim_buf_set_keymap(0, "n", "1", ":q!<CR>", { noremap = true, silent = true })
            -- Jump to selected line
            vim.cmd(tostring(selection.value.line))
            vim.cmd "normal! zt"
          end
        end)
        return true
      end,
    })
    :find()
end

-- All pickers (builtins + custom)
M.all_pickers = function(opts)
  opts = opts or {}
  local builtin = require "telescope.builtin"

  -- Get builtin picker names
  local picker_list = {}
  for name, _ in pairs(builtin) do
    table.insert(picker_list, { name = name, type = "builtin" })
  end

  -- Add custom pickers
  table.insert(picker_list, { name = "tldr", type = "custom" })
  table.insert(picker_list, { name = "cheat", type = "custom" })
  table.insert(picker_list, { name = "shellcheck", type = "custom" })
  table.insert(picker_list, { name = "bash_bible", type = "custom" })

  table.sort(picker_list, function(a, b)
    return a.name < b.name
  end)

  pickers
    .new(opts, {
      prompt_title = "All Pickers",
      finder = finders.new_table {
        results = picker_list,
        entry_maker = function(entry)
          local display = entry.type == "custom" and ("★ " .. entry.name) or entry.name
          return {
            value = entry,
            display = display,
            ordinal = entry.name,
          }
        end,
      },
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            local entry = selection.value
            if entry.type == "custom" then
              M[entry.name](opts)
            else
              require("telescope.builtin")[entry.name](opts)
            end
          end
        end)
        return true
      end,
    })
    :find()
end

return M
