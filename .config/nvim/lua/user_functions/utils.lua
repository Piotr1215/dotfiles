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

-- Shell command input with floating buffer (supports C-r registers)
local shell_input_state = {}

function _G._shell_omnifunc(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local col = vim.fn.col "." - 1
    local start = col
    while start > 0 and line:sub(start, start):match "[^%s]" do
      start = start - 1
    end
    return start
  end
  local line = vim.api.nvim_get_current_line()
  local ctype = line:find " " and "file" or "shellcmd"
  return vim.fn.getcompletion(base, ctype)
end

local function insert_output_at_pos(output, orig_buf, orig_win, orig_pos)
  output = output:gsub("\n$", "") .. " "
  local lines = vim.split(output, "\n")
  if #lines == 0 then
    return
  end

  local row, col = orig_pos[1], orig_pos[2]
  local current = vim.api.nvim_buf_get_lines(orig_buf, row - 1, row, false)[1] or ""
  local before, after = current:sub(1, col), current:sub(col + 1)

  if #lines == 1 then
    vim.api.nvim_buf_set_lines(orig_buf, row - 1, row, false, { before .. lines[1] .. after })
    vim.api.nvim_win_set_cursor(orig_win, { row, col + #lines[1] })
  else
    lines[1] = before .. lines[1]
    lines[#lines] = lines[#lines] .. after
    vim.api.nvim_buf_set_lines(orig_buf, row - 1, row, false, lines)
    vim.api.nvim_win_set_cursor(orig_win, { row + #lines - 1, #lines[#lines] - #after })
  end
end

function _G.insert_command_output()
  local s = shell_input_state
  s.orig_buf = vim.api.nvim_get_current_buf()
  s.orig_win = vim.api.nvim_get_current_win()
  s.orig_pos = vim.api.nvim_win_get_cursor(0)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = 80,
    height = 1,
    style = "minimal",
    border = "rounded",
    title = " $ (Tab=complete) ",
    title_pos = "left",
  })

  vim.bo[buf].omnifunc = "v:lua._shell_omnifunc"
  require("cmp").setup.buffer { enabled = false }
  vim.cmd "startinsert"

  local close = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    vim.api.nvim_set_current_win(s.orig_win)
  end

  local execute = function()
    local cmd = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    close()
    if cmd ~= "" then
      insert_output_at_pos(vim.fn.system(cmd), s.orig_buf, s.orig_win, s.orig_pos)
    end
    vim.cmd "startinsert"
  end

  vim.keymap.set("i", "<CR>", function()
    if vim.fn.pumvisible() == 1 then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-y>", true, false, true), "n", false)
    else
      execute()
    end
  end, { buffer = buf })
  vim.keymap.set("i", "<Esc>", close, { buffer = buf })
  vim.keymap.set("i", "<C-c>", close, { buffer = buf })
  vim.keymap.set("i", "<Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-n>" or "<C-x><C-o>"
  end, { buffer = buf, expr = true })
  vim.keymap.set("i", "<S-Tab>", "<C-p>", { buffer = buf })
end

vim.keymap.set("i", "<C-x>", _G.insert_command_output, { noremap = true, silent = true, nowait = true })
return M
