-- LSP and LS Installer
require "lspconfig"
require("nvim-dap-virtual-text").setup()

-- Diagnostic keymaps
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Go to previous diagnostic message" })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Go to next diagnostic message" })
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Open floating diagnostic message" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostics list" })

local on_attach = function(_, bufnr)
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
  nmap("<C-k>", vim.lsp.buf.signature_help, "Signature Documentation")

  -- Lesser used LSP functionality
  nmap("<leader>wa", vim.lsp.buf.add_workspace_folder, "[W]orkspace [A]dd Folder")
  nmap("<leader>wr", vim.lsp.buf.remove_workspace_folder, "[W]orkspace [R]emove Folder")
  nmap("<leader>wl", function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, "[W]orkspace [L]ist Folders")

  nmap("<c-f>", "<cmd>lua vim.lsp.buf.format({ async = true })<CR>", "Format Buffer")

  nmap("<leader>br", require("dap").toggle_breakpoint, "Toggle Breakpoint")
  nmap("<leader>ac", "<cmd>lua require('lspsaga.codeaction').code_action()<CR>", "Code Action")
  vim.keymap.set({ "n", "v" }, "<leader>caa", "<cmd>Lspsaga code_action<CR>", { silent = true })
end

local lspconfig = require "lspconfig"
lspconfig.pyright.setup {}
lspconfig.lua_ls.setup {
  settings = {
    Lua = {
      diagnostics = {
        globals = { "vim" },
      },
      hint = { enable = true },
    },
  },
}

require("lspconfig").marksman.setup {}

local configs = require "lspconfig.configs"
-- Check if it's already defined for when reloading this file.
configs.up = {
  default_config = {
    cmd = { "up", "xpls", "serve" },
    filetypes = { "yaml" },
    root_dir = lspconfig.util.root_pattern "crossplane.yaml",
  },
}

-- require("lspconfig")['up'].setup({
-- lsp_on_attach = true
-- })

local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require("cmp_nvim_lsp").default_capabilities()

lspconfig.gopls.setup {
  cmd = { "gopls" },
  -- for postfix snippets and analyzers
  capabilities = capabilities,
  settings = {
    gopls = {
      experimentalPostfixCompletions = true,
      analyses = {
        unusedparams = true,
        shadow = true,
      },
      staticcheck = true,
      hints = {
        enabled = true,
        rangeVariableTypes = true,
        prameterNames = true,
        functionTypeParameters = true,
        constantValues = true,
        compositeLiteralTypes = true,
        compositeLiteralFields = true,
        assignVariableTypes = true,
      },
    },
  },
  on_attach = on_attach,
}
