-- Rustaceanvim setup (replacement for rust-tools.nvim)
-- Configuration is done via vim.g.rustaceanvim
vim.g.rustaceanvim = {
  tools = {
    hover_actions = {
      auto_focus = true,
    },
  },
  server = {
    on_attach = function(_, bufnr)
      -- Hover actions (rustaceanvim uses :RustLsp commands)
      vim.keymap.set("n", "<leader>ar", function()
        vim.cmd.RustLsp("hover", "actions")
      end, { buffer = bufnr, desc = "Rust hover actions" })

      -- Code action groups
      vim.keymap.set("n", "<leader>ag", function()
        vim.cmd.RustLsp "codeAction"
      end, { buffer = bufnr, desc = "Rust code action" })

      vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr })
      -- jump to definition
      vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = bufnr })
      -- Rename symbol
      vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { buffer = bufnr })
      -- Vim commands to move through diagnostics.
      vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Go to previous diagnostic message" })
      vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Go to next diagnostic message" })

      -- Use Neovim's default grr for references

      -- codeaction
      vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { buffer = bufnr })

      -- breakpoint
      vim.keymap.set("n", "<leader>tb", require("dap").toggle_breakpoint, { buffer = bufnr })
    end,
    settings = {
      -- rust-analyzer settings
      ["rust-analyzer"] = {
        -- enable clippy on save
        checkOnSave = {
          command = "clippy",
        },
      },
    },
  },
}
