-- LSP and LS Installer
require("nvim-dap-virtual-text").setup()
local def = require "lsp.default-lsp"
local lspconfig = require "lspconfig"
lspconfig.lua_ls.setup {
  capabilities = def.capabilities,
  on_attach = def.on_attach,
  signatureHelp = { enable = true },

  settings = {
    Lua = {
      runtime = {
        version = "LuaJIT",
      },
      diagnostics = {
        globals = { "vim" },
      },
      hint = { enable = true },
      signatureHelp = { enable = true },
    },
  },
}

require("lspconfig").marksman.setup {}

local configs = require "lspconfig.configs"
-- Check if it's already defined for when reloading this file.
configs.up = {
  default_config = {
    cmd = { "up", "xpls", "serve", "--verbose" },
    filetypes = { "yaml" },
    root_dir = lspconfig.util.root_pattern "crossplane.yaml",
  },
}

require("lspconfig")["up"].setup {
  cmd = { "up", "xpls", "serve", "--verbose" },
  filetypes = { "yaml" },
  root_dir = lspconfig.util.root_pattern "crossplane.yaml",
  on_attach = def.on_attach,
}

require("lspconfig").bashls.setup {
  filetypes = { "sh", "zsh" },
}

require("lspconfig")["yamlls"].setup {
  {
    on_attach = def.on_attach,
    capabilities = def.capabilities,
    filetypes = { "yaml", "yml" },
    flags = { debounce_test_changes = 150 },
    settings = {
      yaml = {
        format = {
          enable = true,
          singleQuote = true,
          printWidth = 120,
        },
        hover = true,
        completion = true,
        validate = true,
      },
      schemas = {
        ["https://json.schemastore.org/github-workflow.json"] = "/.github/workflows/*",
        ["http://json.schemastore.org/github-action"] = { ".github/action.{yml,yaml}" },
      },
      schemaStore = {
        enable = true,
        url = "https://www.schemastore.org/api/json/catalog.json",
      },
    },
  },
}
require("ionide").setup {
  on_attach = def.on_attach,
  capabilities = def.capabilities,
}
-- PROJECT: lsp_lines
-- When using lsp_lines, this needs to be disabled
vim.diagnostic.config {
  virtual_text = false,
}
lspconfig.gopls.setup {
  cmd = { "gopls" },
  -- for postfix snippets and analyzers
  capabilities = def.capabilities,
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
  on_attach = def.on_attach,
}
