-- Markdown reading mode: the same buffer in the same window, switched between
-- a view tuned for reading and the normal editing view. Reading hides the
-- gutter, spell marks and cursorline, centers the text with no-neck-pain,
-- renders the cursor line too (no raw text under the cursor), moves by screen
-- lines and locks the buffer. Toggle with <leader>mr; q also leaves.
local M = {}

local win_opts =
  { "number", "relativenumber", "signcolumn", "foldcolumn", "cursorline", "spell", "colorcolumn", "list" }
local reading_values = {
  number = false,
  relativenumber = false,
  signcolumn = "no",
  foldcolumn = "0",
  cursorline = false,
  spell = false,
  colorcolumn = "",
  list = false,
}
local reader_keys = { "j", "k", "q" }

-- Show or hide raw text on the cursor line in this buffer's render-markdown
-- config. Uses the plugin's per-buffer state, so it is wrapped in pcall.
local function set_anti_conceal(buf, enabled)
  pcall(function()
    local config = require("render-markdown.state").get(buf)
    config.anti_conceal.enabled = enabled
    require("render-markdown").buf_enable()
  end)
end

local function set_centered(on)
  local ok, nnp = pcall(require, "no-neck-pain")
  if not ok then
    return
  end
  local active = _G.NoNeckPain and _G.NoNeckPain.state and _G.NoNeckPain.state.enabled
  if on and not active then
    nnp.enable()
  elseif not on and active then
    nnp.disable()
  end
end

-- Whether the current buffer is in reading mode.
function M.is_reading(buf)
  return vim.b[buf or 0].markdown_reading == true
end

-- Enter reading mode in the current window.
function M.enter()
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  if M.is_reading(buf) then
    return
  end
  local saved = { modifiable = vim.bo[buf].modifiable, win = {} }
  for _, name in ipairs(win_opts) do
    saved.win[name] = vim.wo[win][name]
    vim.wo[win][name] = reading_values[name]
  end
  vim.b[buf].markdown_reader_saved = saved
  vim.b[buf].markdown_reading = true
  vim.bo[buf].modifiable = false

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "j", "gj", opts)
  vim.keymap.set("n", "k", "gk", opts)
  vim.keymap.set("n", "q", M.leave, opts)

  set_anti_conceal(buf, false)
  set_centered(true)
end

-- Leave reading mode and restore the editing view.
function M.leave()
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  if not M.is_reading(buf) then
    return
  end
  local saved = vim.b[buf].markdown_reader_saved or { modifiable = true, win = {} }
  for name, value in pairs(saved.win) do
    vim.wo[win][name] = value
  end
  vim.bo[buf].modifiable = saved.modifiable
  vim.b[buf].markdown_reading = false
  for _, key in ipairs(reader_keys) do
    pcall(vim.keymap.del, "n", key, { buffer = buf })
  end

  set_anti_conceal(buf, true)
  set_centered(false)
end

function M.toggle()
  if M.is_reading() then
    M.leave()
  else
    M.enter()
  end
end

return M
