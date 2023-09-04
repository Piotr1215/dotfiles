vim.cmd('set completeopt=menuone,noinsert,noselect')
vim.cmd('set shortmess+=c')

-- Treesitter folding
vim.cmd('set foldmethod=marker')
vim.cmd('set foldmarker={{{,}}}')

vim.api.nvim_create_autocmd({ "BufWritePost" }, {
  pattern = { "*.rs" },
  command = "silent! RustFmt",
})
