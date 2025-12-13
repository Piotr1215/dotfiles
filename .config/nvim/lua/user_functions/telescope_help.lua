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
