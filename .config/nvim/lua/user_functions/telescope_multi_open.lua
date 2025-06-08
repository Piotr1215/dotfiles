-- ~/.config/nvim/lua/user_functions/telescope_multi_open.lua
local action_state = require "telescope.actions.state"
local actions = require "telescope.actions"

local M = {}

-- Multi-pane layout function for selected files only
local function open_selected_in_layout(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  
  -- Get multi-selected entries first
  local multi_selections = current_picker:get_multi_selection()
  local selected_entries = {}
  
  if #multi_selections > 0 then
    -- User has made multi-selections, use those
    for _, entry in ipairs(multi_selections) do
      -- Handle different entry types - try multiple ways to get file path
      local file_path = entry[1] or entry.value or entry.filename or entry.path
      if file_path then
        table.insert(selected_entries, file_path)
      end
    end
  else
    -- No multi-selections, use current selection
    local current_selection = action_state.get_selected_entry()
    if current_selection then
      local file_path = current_selection[1] or current_selection.value or current_selection.filename or current_selection.path
      if file_path then
        table.insert(selected_entries, file_path)
      end
    end
  end
  
  actions.close(prompt_bufnr)
  
  if #selected_entries == 0 then
    vim.notify("No files selected", vim.log.levels.WARN)
    return
  end
  
  -- Limit the number of files to prevent "too many open files" error
  local max_files = 20
  if #selected_entries > max_files then
    vim.notify("Too many files selected (" .. #selected_entries .. "). Opening first " .. max_files .. " files.", vim.log.levels.WARN)
    local truncated = {}
    for i = 1, max_files do
      table.insert(truncated, selected_entries[i])
    end
    selected_entries = truncated
  end
  
  if #selected_entries == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(selected_entries[1]))
  elseif #selected_entries == 2 then
    vim.cmd("edit " .. vim.fn.fnameescape(selected_entries[1]))
    vim.cmd("vs " .. vim.fn.fnameescape(selected_entries[2]))
  else
    vim.cmd("edit " .. vim.fn.fnameescape(selected_entries[1]))
    vim.cmd("vs " .. vim.fn.fnameescape(selected_entries[2]))
    if #selected_entries >= 3 then
      vim.cmd("split " .. vim.fn.fnameescape(selected_entries[3]))
    end
    -- Open remaining files in tabs, but with a reasonable limit
    local max_tabs = math.min(10, #selected_entries - 3) -- Max 10 additional tabs
    for i = 4, 3 + max_tabs do
      if selected_entries[i] then
        vim.cmd("tabedit " .. vim.fn.fnameescape(selected_entries[i]))
      end
    end
    
    if #selected_entries > 13 then
      vim.notify("Opened first 13 files in panes/tabs. " .. (#selected_entries - 13) .. " files skipped.", vim.log.levels.INFO)
    end
  end
end

-- Function to add the multi-open mapping to any picker's attach_mappings
function M.enhance_picker_mappings(original_attach_mappings)
  return function(prompt_bufnr, map)
    -- Add our multi-open mapping
    map("i", "<M-a>", function()
      open_selected_in_layout(prompt_bufnr)
    end)
    
    map("n", "<M-a>", function()
      open_selected_in_layout(prompt_bufnr)
    end)
    
    -- Call original attach_mappings if it exists
    if original_attach_mappings then
      return original_attach_mappings(prompt_bufnr, map)
    else
      return true
    end
  end
end

-- Global monkey patch approach using telescope.pickers.new
function M.setup()
  local pickers = require "telescope.pickers"
  
  -- Store the original picker.new function
  local original_picker_new = pickers.new
  
  -- Replace with our enhanced version
  pickers.new = function(opts, config)
    -- Enhance attach_mappings if this looks like a file picker
    if config and config.finder then
      local original_attach = config.attach_mappings
      
      config.attach_mappings = function(prompt_bufnr, map)
        -- Add our multi-open mapping to ALL pickers
        map("i", "<M-a>", function()
          open_selected_in_layout(prompt_bufnr)
        end)
        
        map("n", "<M-a>", function()
          open_selected_in_layout(prompt_bufnr)
        end)
        
        -- Call original attach_mappings if it exists
        if original_attach then
          return original_attach(prompt_bufnr, map)
        else
          return true
        end
      end
    end
    
    -- Call the original function with our modified config
    return original_picker_new(opts, config)
  end
  
end

return M