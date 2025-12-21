-- ~/.config/nvim/lua/user_functions/fold_focus.lua
-- Focus on lines matching a pattern by folding non-matching lines
-- Saves and restores previous fold settings

local M = {}

-- Store original fold settings per buffer
M.saved_settings = {}

function M.focus(pattern)
  local bufnr = vim.api.nvim_get_current_buf()

  -- Save current fold settings if not already in focus mode
  if not M.saved_settings[bufnr] then
    M.saved_settings[bufnr] = {
      foldmethod = vim.wo.foldmethod,
      foldexpr = vim.wo.foldexpr,
      foldlevel = vim.wo.foldlevel,
      foldenable = vim.wo.foldenable,
    }
  end

  -- Escape pattern for vim regex
  local escaped = vim.fn.escape(pattern, "/\\")

  -- Set expression folding to hide non-matching lines
  vim.wo.foldmethod = "expr"
  vim.wo.foldexpr = "getline(v:lnum)=~'" .. escaped .. "'?0:1"
  vim.wo.foldlevel = 0
  vim.wo.foldenable = true
end

function M.restore()
  local bufnr = vim.api.nvim_get_current_buf()
  local saved = M.saved_settings[bufnr]

  if saved then
    vim.wo.foldmethod = saved.foldmethod
    vim.wo.foldexpr = saved.foldexpr
    vim.wo.foldlevel = saved.foldlevel
    vim.wo.foldenable = saved.foldenable
    M.saved_settings[bufnr] = nil
  end
end

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()

  if M.saved_settings[bufnr] then
    M.restore()
  else
    vim.ui.input({ prompt = "Focus pattern: " }, function(pattern)
      if pattern and pattern ~= "" then
        M.focus(pattern)
      end
    end)
  end
end

function M.focus_word()
  local word = vim.fn.expand "<cword>"
  if word ~= "" then
    M.focus(word)
  end
end

function M.focus_visual()
  -- Get visual selection
  vim.cmd 'noau normal! "vy'
  local selection = vim.fn.getreg "v"
  selection = selection:gsub("\n", "")
  if selection ~= "" then
    M.focus(selection)
  end
end

function M.yank_visible()
  local lines = {}
  local total = vim.api.nvim_buf_line_count(0)
  local i = 1
  while i <= total do
    local closed = vim.fn.foldclosed(i)
    if closed == -1 then
      -- Line is visible
      table.insert(lines, vim.fn.getline(i))
      i = i + 1
    else
      -- Skip to end of fold
      i = vim.fn.foldclosedend(i) + 1
    end
  end
  local text = table.concat(lines, "\n")
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
end

-- Keymaps
-- <leader>zp - focus on Pattern (prompts for input)
-- <leader>z* - focus on word under cursor / visual selection
-- <leader>zP - restore Previous fold settings
-- <leader>zy - yank visible lines only
vim.keymap.set("n", "<leader>zp", M.toggle, { desc = "Focus fold on pattern (toggle)" })
vim.keymap.set("n", "<leader>z*", M.focus_word, { desc = "Focus fold on word under cursor" })
vim.keymap.set("v", "<leader>z*", M.focus_visual, { desc = "Focus fold on visual selection" })
vim.keymap.set("n", "<leader>zP", M.restore, { desc = "Restore previous fold settings" })
vim.keymap.set("n", "<leader>zy", M.yank_visible, { desc = "Yank visible (non-folded) lines" })

return M
