vim.api.nvim_buf_set_keymap(0, "n", "<leader>gr", ":GoRun<CR>", { noremap = false })
vim.api.nvim_buf_set_keymap(0, "n", "<leader>ggr", ":GoGenReturn<CR>", { noremap = false })

local goSettings = vim.api.nvim_create_augroup("GoSettings", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  pattern = "go",
  callback = function()
    vim.api.nvim_buf_set_keymap(0, "n", "<leader>fld", ":%g/ {/normal! zf%<CR>", { noremap = true, silent = true })
  end,
  group = goSettings,
})
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*test*.go",
  command = "silent! GoTestFile",
  group = goSettings,
})
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.go",
  command = "silent! Neoformat",
  group = goSettings,
})
