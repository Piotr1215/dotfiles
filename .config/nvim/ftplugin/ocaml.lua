-- OCaml specific settings

-- Format on save using ocamlformat
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.ml,*.mli",
  callback = function()
    -- Only format if ocamlformat is available
    if vim.fn.executable("ocamlformat") == 1 then
      vim.lsp.buf.format({ async = false })
    end
  end,
})

-- Set proper indentation for OCaml
vim.opt_local.expandtab = true
vim.opt_local.shiftwidth = 2
vim.opt_local.tabstop = 2
vim.opt_local.softtabstop = 2

-- Enable comment continuation
vim.opt_local.formatoptions:append("ro")

-- Set comment string
vim.opt_local.commentstring = "(* %s *)"

-- Useful keymaps for OCaml development
local opts = { noremap = true, silent = true, buffer = true }

-- Type hints on hover (K is usually default but let's be explicit)
vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)

-- Show type signature
vim.keymap.set("n", "<leader>ot", vim.lsp.buf.signature_help, opts)

-- Run dune build in current directory
vim.keymap.set("n", "<leader>ob", ":!dune build<CR>", opts)

-- Run dune exec for current file
vim.keymap.set("n", "<leader>or", ":!dune exec ./%:t:r.exe<CR>", opts)

-- Open utop REPL
vim.keymap.set("n", "<leader>ou", ":terminal utop<CR>", opts)

-- Jump between .ml and .mli files
vim.keymap.set("n", "<leader>oi", function()
  local file = vim.fn.expand("%:r")
  local ext = vim.fn.expand("%:e")
  if ext == "ml" then
    vim.cmd("edit " .. file .. ".mli")
  elseif ext == "mli" then
    vim.cmd("edit " .. file .. ".ml")
  end
end, opts)