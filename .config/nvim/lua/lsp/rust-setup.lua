local rt = require "rust-tools"

rt.setup {
  tools = {
    -- how to execute terminal commands
    -- options right now: termopen / quickfix
    executor = require("rust-tools/executors").quickfix,
    hover_actions = {
      auto_focus = true,
    },
  },
  server = {
    settings = {
      -- to enable rust-analyzer settings visit:
      -- https://github.com/rust-analyzer/rust-analyzer/blob/master/docs/user/generated_config.adoc
      ["rust-analyzer"] = {
        -- enable clippy on save
        checkOnSave = {
          command = "clippy",
        },
      },
    },
    on_attach = function(_, bufnr)
      -- Hover actions
      vim.keymap.set("n", "<leader>ar", rt.hover_actions.hover_actions, { buffer = bufnr })
      -- Code action groups
      vim.keymap.set("n", "<leader>ag", rt.code_action_group.code_action_group, { buffer = bufnr })
      vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr })
      -- jump to definition
      vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = bufnr })
      -- Rename symbol
      vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { buffer = bufnr })
      --       Vim commands to move through diagnostics.
      vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Go to previous diagnostic message" })
      vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Go to next diagnostic message" })

      -- Find reference
      vim.keymap.set("n", "gr", require("telescope.builtin").lsp_references, { buffer = bufnr })

      -- codeaction
      vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { buffer = bufnr })

      -- breakpoint
      vim.keymap.set("n", "<leader>tb", require("dap").toggle_breakpoint, { buffer = bufnr })
    end,
  },
}
