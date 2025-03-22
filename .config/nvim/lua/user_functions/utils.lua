-- ~/.config/nvim/lua/user_functions/utils.lua
local M = {}

-- Key binding for this is defined in markdown.lua
function M.bracket_link()
  -- Get the visual selection boundaries
  local start_line = vim.fn.line "'<"
  local start_col = vim.fn.col "'<"
  local end_line = vim.fn.line "'>"
  local end_col = vim.fn.col "'>"

  -- Get the selected text
  local lines = vim.fn.getline(start_line, end_line)
  if #lines == 0 then
    return
  end

  -- Handle single line selection
  if start_line == end_line then
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    -- Handle multi-line selection
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end

  local selected_text = table.concat(lines, " ")
  local url = vim.fn.getreg "+"

  -- Create the formatted link
  local formatted_text = "[" .. selected_text .. "](" .. url .. ")"

  -- Replace the selection with the formatted text
  vim.api.nvim_buf_set_text(0, start_line - 1, start_col - 1, end_line - 1, end_col, { formatted_text })
end

function M.print_current_file_dir()
  local dir = vim.fn.expand "%:p:h"
  if dir ~= "" then
    print(dir)
  end
end

function M.reload_module(name)
  package.loaded[name] = nil
  return require(name)
end

-- Function to reload the current Lua file
function M.reload_current_file()
  local current_file = vim.fn.expand "%:p"

  if current_file:match "%.lua$" then
    vim.cmd("luafile " .. current_file)
    print("Reloaded file: " .. current_file)
  else
    print("Current file is not a Lua file: " .. current_file)
  end
end

function M.insert_file_path()
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  require("telescope.builtin").find_files {
    cwd = "~/dev", -- Set the directory to search
    attach_mappings = function(_, map)
      map("i", "<CR>", function(prompt_bufnr)
        local selected_file = action_state.get_selected_entry(prompt_bufnr).path
        actions.close(prompt_bufnr)
        -- Get absolute path
        local absolute_path = vim.fn.fnamemodify(selected_file, ":p")
        -- Ask the user if they want to insert the full path or just the file name
        local choice = vim.fn.input "Insert full path or file name? (n[ame]/p[ath]): "
        local text_to_insert
        if choice == "p" then
          text_to_insert = absolute_path
        elseif choice == "n" then
          text_to_insert = vim.fn.fnamemodify(absolute_path, ":t")
        end
        -- Move the cursor back one position
        local col = vim.fn.col "." - 1
        vim.fn.cursor(vim.fn.line ".", col)
        -- Insert the text at the cursor position
        vim.api.nvim_put({ text_to_insert }, "c", true, true)
      end)
      return true
    end,
  }
end

vim.api.nvim_set_keymap(
  "i",
  "<M-i>",
  "<Cmd>lua require('user_functions.utils').insert_file_path()<CR>",
  { noremap = true, silent = true }
)
function M.create_floating_scratch(content)
  -- Get editor dimensions
  local width = vim.api.nvim_get_option "columns"
  local height = vim.api.nvim_get_option "lines"

  -- Calculate the floating window size
  local win_height = math.ceil(height * 0.8) + 2 -- Adding 2 for the border
  local win_width = math.ceil(width * 0.8) + 2 -- Adding 2 for the border

  -- Calculate window's starting position
  local row = math.ceil((height - win_height) / 2)
  local col = math.ceil((width - win_width) / 2)

  -- Create a buffer and set it as a scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "sh") -- for syntax highlighting

  -- Create the floating window with a border and set some options
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = win_width,
    height = win_height,
    border = "single", -- You can also use 'double', 'rounded', or 'solid'
  })

  -- Check if we've got content to populate the buffer with
  if content then
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, content)
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, { "This is a scratch buffer in a floating window." })
  end

  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "cursorline", true)

  -- Map 'q' to close the buffer in this window
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":q!<CR>", { noremap = true, silent = true })
end

-- Function to insert command output at cursor position without trailing newline
function _G.insert_command_output()
  vim.ui.input({ prompt = "Command: " }, function(cmd)
    if cmd then
      local output = vim.fn.system(cmd)
      -- Remove trailing newline
      output = string.gsub(output, "\n$", "")

      -- Get cursor position
      local pos = vim.api.nvim_win_get_cursor(0)
      local row, col = pos[1], pos[2]

      -- Split output by newlines
      local lines = {}
      for line in string.gmatch(output .. "\n", "(.-)\n") do
        table.insert(lines, line)
      end

      if #lines == 0 then
        return
      end

      -- Get current line and split it
      local current_line = vim.api.nvim_get_current_line()
      local before_cursor = string.sub(current_line, 1, col)
      local after_cursor = string.sub(current_line, col + 1)

      -- Prepare new lines
      local new_lines = {}

      -- First line combines with the beginning of the current line
      table.insert(new_lines, before_cursor .. lines[1])

      -- Add middle lines as is
      for i = 2, #lines - 1 do
        table.insert(new_lines, lines[i])
      end

      -- Last line combines with the end of the current line
      if #lines > 1 then
        table.insert(new_lines, lines[#lines] .. after_cursor)
      else
        -- If there's only one line, we've already handled it
        new_lines[1] = new_lines[1] .. after_cursor
      end

      -- Replace the current line with our new lines
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, new_lines)

      -- Set cursor position to the end of the inserted text
      if #lines > 1 then
        vim.api.nvim_win_set_cursor(0, { row + #lines - 1, #lines[#lines] })
      else
        vim.api.nvim_win_set_cursor(0, { row, col + #lines[1] })
      end
    end
  end)
end

vim.keymap.set("i", "<C-x>c", "<C-o>:lua insert_command_output()<CR>", { noremap = true, silent = true })
return M
