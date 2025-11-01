-- LaTeX LSP configuration
local def = require "lsp.default-lsp"

-- LaTeX syntax checking with texlab
vim.lsp.config("texlab", {
  capabilities = def.capabilities,
  filetypes = { "tex", "latex", "bib", "plaintex" },
  settings = {
    texlab = {
      build = {
        executable = "latexmk",
        args = { "-pdf", "-interaction=nonstopmode", "-synctex=1", "%f" },
        onSave = false, -- VimTeX handles compilation
        forwardSearchAfter = false,
      },
      auxDirectory = ".",
      forwardSearch = {
        executable = "zathura",
        args = { "--synctex-forward", "%l:1:%f", "%p" },
      },
      chktex = {
        onOpenAndSave = true,
        onEdit = false,
      },
      diagnosticsDelay = 300,
      latexFormatter = "latexindent",
      latexindent = {
        modifyLineBreaks = false,
      },
    },
  },
})

-- LaTeX grammar/spell checking with ltex-ls-plus
vim.lsp.config("ltex", {
  cmd = { vim.fn.expand "~/.local/share/nvim/mason/bin/ltex-ls-plus" },
  capabilities = def.capabilities,
  filetypes = { "tex", "latex", "bib", "markdown" },
  settings = {
    ltex = {
      language = "en-US",
      additionalRules = {
        enablePickyRules = true,
        motherTongue = "en-US",
      },
      checkFrequency = "save",
      diagnosticSeverity = "information",
      -- Disable rules that might be annoying
      disabledRules = {
        ["en-US"] = { "MORFOLOGIK_RULE_EN_US" },
      },
      -- Custom dictionary
      dictionary = {},
      -- Ignore LaTeX commands
      latex = {
        commands = {},
        environments = {},
      },
    },
  },
})

-- Enable LaTeX LSP servers
vim.lsp.enable { "texlab", "ltex" }
