-- LSP and LS Installer
require("nvim-dap-virtual-text").setup {}
local lspconfig = require "lspconfig"
local def = require "lsp.default-lsp"
lspconfig.lua_ls.setup {
  autostart = true,
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
local nvim_lsp = require "lspconfig"
lspconfig.terraformls.setup {}
lspconfig.tflint.setup {}
nvim_lsp.denols.setup {
  on_attach = def.on_attach,
  root_dir = nvim_lsp.util.root_pattern("deno.json", "deno.jsonc"),
}

nvim_lsp.ts_ls.setup {
  on_attach = def.on_attach,
  root_dir = nvim_lsp.util.root_pattern "package.json",
  single_file_support = false,
}

-- vale_ls will autoload for all subdirectories in ~/loft/ by using .nvimrc
-- to prevent loading it in other projects, it can be loaded manually with a User command
vim.api.nvim_create_user_command("LspStartVale", function()
  require("lspconfig").vale_ls.setup {
    root_dir = require("lspconfig").util.root_pattern ".vale.ini",
    filetypes = { "markdown", "mdx" },
  }
  vim.cmd "LspStart vale_ls"
end, {})

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
  virtual_text = true,
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
