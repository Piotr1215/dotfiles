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

      -- K, gd, <leader>rn retired: rustaceanvim uses the native vim.lsp client,
      -- so the global LspAttach autocmd (default-lsp.lua) already sets these
      -- (K is also stock 0.12). No need to redefine them per-buffer here.
      -- Vim commands to move through diagnostics.
      vim.keymap.set("n", "[d", function()
        vim.diagnostic.jump { count = -1, float = true }
      end, { desc = "Go to previous diagnostic message" })
      vim.keymap.set("n", "]d", function()
        vim.diagnostic.jump { count = 1, float = true }
      end, { desc = "Go to next diagnostic message" })

      -- Use Neovim's default grr for references

      -- <leader>ca retired: set by the global LspAttach autocmd (default-lsp.lua);
      -- code_action is also stock `gra` in 0.12.

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
