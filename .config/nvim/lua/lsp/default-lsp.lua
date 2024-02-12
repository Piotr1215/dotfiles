local M = {}

M.capabilities = require("cmp_nvim_lsp").default_capabilities()

-- Diagnostic keymaps
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Go to previous diagnostic message" })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Go to next diagnostic message" })
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Open floating diagnostic message" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostics list" })

M.on_attach = function(_, bufnr)
  local nmap = function(keys, func, desc)
    if desc then
      desc = "LSP: " .. desc
    end

    vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
  end

  nmap("<leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")

  nmap("gd", vim.lsp.buf.definition, "[G]oto [D]efinition")
  nmap("gI", vim.lsp.buf.implementation, "[G]oto [I]mplementation")
  nmap("gr", '<cmd>lua require("lspsaga.provider").lsp_finder()<CR>', "Find Reference")
  nmap("<leader>rn", "<cmd>lua require('lspsaga.rename').rename()<CR>", "Rename Symbol")
  nmap("<leader>D", vim.lsp.buf.type_definition, "Type [D]efinition")
  nmap("<leader>ds", require("telescope.builtin").lsp_document_symbols, "[D]ocument [S]ymbols")
  nmap("<leader>ws", require("telescope.builtin").lsp_dynamic_workspace_symbols, "[W]orkspace [S]ymbols")

  -- See `:help K` for why this keymap
  nmap("K", "<cmd>lua require('lspsaga.hover').render_hover_doc()<CR>", "Hover Documentation")

  -- Lesser used LSP functionality
  nmap("<leader>wA", vim.lsp.buf.add_workspace_folder, "[W]orkspace [A]dd Folder")
  nmap("<leader>wr", vim.lsp.buf.remove_workspace_folder, "[W]orkspace [R]emove Folder")
  nmap("<leader>wl", function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, "[W]orkspace [L]ist Folders")

  nmap("<c-f>", "<cmd>lua vim.lsp.buf.format({ async = true })<CR>", "Format Buffer")

  nmap("<leader>br", require("dap").toggle_breakpoint, "Toggle Breakpoint")
  -- nmap("<leader>cac", ":Lspsaga code_action<CR>", "Code Action")
  vim.keymap.set({ "n", "v" }, "<leader>caa", "<cmd>Lspsaga code_action<CR>", { silent = true })
end

return M
