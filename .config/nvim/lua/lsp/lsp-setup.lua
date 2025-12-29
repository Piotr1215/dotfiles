-- LSP and LS Installer
-- Testing comment for suggestions
require("nvim-dap-virtual-text").setup {}
local def = require "lsp.default-lsp"

-- Configure lua_ls using the new API
--
vim.lsp.config("lua_ls", {
  autostart = true,
  attach = def.on_attach,
  capabilities = def.capabilities,
  signatureHelp = { enable = true },
  root_dir = function(fname)
    return vim.fs.root(fname, { ".luarc.json", ".git", "lua" })
  end,

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

-- Configure terraformls and tflint using the new API
vim.lsp.config("terraformls", {})
vim.lsp.config("tflint", {})

-- OCaml LSP setup for devbox environments
vim.lsp.config("ocamllsp", {
  cmd = { "ocamllsp" },
  capabilities = def.capabilities,
  filetypes = { "ocaml", "ocaml.menhir", "ocaml.interface", "ocaml.ocamllex", "reason" },
  root_dir = function(fname)
    return vim.fs.root(fname, { "*.opam", "dune-project", "dune-workspace", ".git" })
  end,
})

vim.lsp.config("denols", {
  root_dir = function(fname)
    return vim.fs.root(fname, { "deno.json", "deno.jsonc" })
  end,
})

vim.lsp.config("ts_ls", {
  root_dir = function(fname)
    return vim.fs.root(fname, { "package.json" })
  end,
  single_file_support = false,
})

-- vale_ls will autoload for all subdirectories in ~/loft/ by using .nvimrc
-- to prevent loading it in other projects, it can be loaded manually with a User command
-- Using custom-built vale-ls from ~/.local/bin to avoid GLIBC issues
vim.api.nvim_create_user_command("LspStartVale", function()
  vim.lsp.config("vale_ls", {
    cmd = { vim.fn.expand "~/.local/bin/vale-ls" },
    root_dir = function(fname)
      return vim.fs.root(fname, { ".vale.ini" })
    end,
    filetypes = { "markdown", "mdx" },
  })
  vim.lsp.enable { "vale_ls" }
end, {})

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

-- PROJECT: lsp_lines
-- When using lsp_lines, this needs to be disabled
vim.diagnostic.config {
  virtual_text = true,
}

vim.lsp.config("zls", {
  capabilities = def.capabilities,
  filetypes = { "zig", "zon" },
  root_dir = function(fname)
    return vim.fs.root(fname, { "build.zig", "zls.json", ".git" })
  end,
  settings = {
    zls = {
      prefer_ast_check_as_child_process = true,
      warn_style = true,
    },
  },
})

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
vim.lsp.enable { "lua_ls", "terraformls", "tflint", "ocamllsp", "denols", "ts_ls", "bashls", "yamlls", "gopls", "zls" }
