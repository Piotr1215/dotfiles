-- Inline shell completion: float a terminal at cursor for real shell tab-completion
-- Trigger: <C-t> in insert or normal mode
-- Exit: <C-d> to accept and insert, <C-c> to cancel

local M = {}

local state = {
  orig_buf = nil,
  orig_win = nil,
  orig_pos = nil,
  term_buf = nil,
  term_win = nil,
}

local function close_float()
  if state.term_win and vim.api.nvim_win_is_valid(state.term_win) then
    vim.api.nvim_win_close(state.term_win, true)
  end
  if state.term_buf and vim.api.nvim_buf_is_valid(state.term_buf) then
    vim.api.nvim_buf_delete(state.term_buf, { force = true })
  end
  state.term_win = nil
  state.term_buf = nil
end

local function extract_content(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- Filter empty lines at end, skip prompt lines
  local result = {}
  for _, line in ipairs(lines) do
    -- Skip empty lines and bare prompts
    if line ~= "" and not line:match "^%s*$" then
      table.insert(result, line)
    end
  end
  return result
end

local function insert_at_cursor(lines)
  if not lines or #lines == 0 then
    return
  end
  vim.api.nvim_set_current_win(state.orig_win)
  vim.api.nvim_set_current_buf(state.orig_buf)
  vim.api.nvim_win_set_cursor(state.orig_win, state.orig_pos)

  -- Insert lines at cursor
  local row = state.orig_pos[1]
  local col = state.orig_pos[2]
  local current_line = vim.api.nvim_buf_get_lines(state.orig_buf, row - 1, row, false)[1] or ""

  if #lines == 1 then
    -- Single line: insert inline
    local before = current_line:sub(1, col)
    local after = current_line:sub(col + 1)
    vim.api.nvim_buf_set_lines(state.orig_buf, row - 1, row, false, { before .. lines[1] .. after })
    vim.api.nvim_win_set_cursor(state.orig_win, { row, col + #lines[1] })
  else
    -- Multi-line: insert as block below cursor line
    local before = current_line:sub(1, col)
    local after = current_line:sub(col + 1)
    -- First line completes current line
    lines[1] = before .. lines[1]
    -- Last line gets the "after" part
    lines[#lines] = lines[#lines] .. after
    vim.api.nvim_buf_set_lines(state.orig_buf, row - 1, row, false, lines)
    vim.api.nvim_win_set_cursor(state.orig_win, { row + #lines - 1, #lines[#lines] - #after })
  end
end

function M.open()
  -- Store original position
  state.orig_buf = vim.api.nvim_get_current_buf()
  state.orig_win = vim.api.nvim_get_current_win()
  state.orig_pos = vim.api.nvim_win_get_cursor(state.orig_win)

  -- Create floating window
  local width = math.min(80, vim.o.columns - 4)
  local height = 8

  state.term_buf = vim.api.nvim_create_buf(false, true)
  state.term_win = vim.api.nvim_open_win(state.term_buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Shell (C-d: accept, C-c: cancel) ",
    title_pos = "center",
  })

  -- Start terminal with zsh
  vim.fn.termopen(os.getenv "SHELL" or "zsh", {
    on_exit = function(_, exit_code, _)
      local content = nil
      if exit_code == 0 then
        content = extract_content(state.term_buf)
      end
      close_float()
      if content and #content > 0 then
        vim.schedule(function()
          insert_at_cursor(content)
        end)
      end
    end,
  })

  -- Enter insert mode in terminal
  vim.cmd "startinsert"

  -- Set up keymaps for this terminal buffer
  local opts = { buffer = state.term_buf, noremap = true, silent = true }

  -- C-c to cancel (exit with non-zero)
  vim.keymap.set("t", "<C-c>", function()
    close_float()
    vim.api.nvim_set_current_win(state.orig_win)
  end, opts)
end

function M.setup()
  vim.keymap.set({ "n", "i" }, "<C-t>", M.open, { desc = "Open inline shell" })
end

return M
