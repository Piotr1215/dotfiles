vim.cmd('set completeopt=menuone,noinsert,noselect')
vim.cmd('set shortmess+=c')

vim.api.nvim_create_autocmd({ "BufWritePost" }, {
  pattern = { "*.rs" },
  command = "RustFmt",
})

