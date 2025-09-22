-- LSP and LS Installer
require("nvim-dap-virtual-text").setup {}
local lspconfig = require "lspconfig"
local def = require "lsp.default-lsp"

-- Configure lua_ls using the new API
vim.lsp.config("lua_ls", {
  autostart = true,
  capabilities = def.capabilities,
  signatureHelp = { enable = true },
  root_dir = lspconfig.util.root_pattern(".luarc.json", ".git", "lua"),

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
})
local nvim_lsp = require "lspconfig"

-- Configure terraformls and tflint using the new API
vim.lsp.config("terraformls", {})
vim.lsp.config("tflint", {})

-- OCaml LSP setup for devbox environments
vim.lsp.config("ocamllsp", {
  cmd = { "ocamllsp" }, -- Uses the one from PATH (devbox provides it)
  capabilities = def.capabilities,
  filetypes = { "ocaml", "ocaml.menhir", "ocaml.interface", "ocaml.ocamllex", "reason" },
  root_dir = lspconfig.util.root_pattern("*.opam", "dune-project", "dune-workspace", ".git"),
})

vim.lsp.config("denols", {
  root_dir = nvim_lsp.util.root_pattern("deno.json", "deno.jsonc"),
})

vim.lsp.config("ts_ls", {
  root_dir = nvim_lsp.util.root_pattern "package.json",
  single_file_support = false,
})

-- vale_ls will autoload for all subdirectories in ~/loft/ by using .nvimrc
-- to prevent loading it in other projects, it can be loaded manually with a User command
vim.api.nvim_create_user_command("LspStartVale", function()
  vim.lsp.config("vale_ls", {
    root_dir = require("lspconfig").util.root_pattern ".vale.ini",
    filetypes = { "markdown", "mdx" },
  })
  vim.lsp.enable { "vale_ls" }
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

vim.lsp.config("up", {
  cmd = { "up", "xpls", "serve", "--verbose" },
  filetypes = { "yaml" },
  root_dir = lspconfig.util.root_pattern "crossplane.yaml",
})

vim.lsp.config("bashls", {
  filetypes = { "sh", "zsh" },
})

vim.lsp.config("yamlls", {
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
})

require("ionide").setup {
  capabilities = def.capabilities,
}

-- PROJECT: lsp_lines
-- When using lsp_lines, this needs to be disabled
vim.diagnostic.config {
  virtual_text = true,
}

vim.lsp.config("gopls", {
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
})

-- Enable all configured LSP servers
vim.lsp.enable { "lua_ls", "terraformls", "tflint", "ocamllsp", "denols", "ts_ls", "up", "bashls", "yamlls", "gopls" }
