local rt = require("rust-tools")

rt.setup({
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
          command = "clippy"
        },
      }
    },
    on_attach = function(_, bufnr)
      -- Hover actions
      vim.keymap.set("n", "<leader>ar", rt.hover_actions.hover_actions, { buffer = bufnr })
      -- Code action groups
      vim.keymap.set("n", "<leader>ag", rt.code_action_group.code_action_group, { buffer = bufnr })
      vim.keymap.set('n', 'K', require('lspsaga.hover').render_hover_doc, { buffer = bufnr })
      -- jump to definition
      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = bufnr })
      -- Rename symbol
      vim.keymap.set('n', '<leader>rn', require('lspsaga.rename').rename, { buffer = bufnr })
      --       Vim commands to move through diagnostics.
      vim.keymap.set('n', 'gj', ':Lspsaga diagnostic_jump_prev<CR>', { buffer = bufnr })
      vim.keymap.set('n', 'gk', ':Lspsaga diagnostic_jump_next<CR>', { buffer = bufnr })

      -- Find reference
      vim.keymap.set('n', 'gr', require("lspsaga.provider").lsp_finder, { buffer = bufnr })

      -- codeaction
      vim.keymap.set('n', '<leader>ac', require('lspsaga.codeaction').code_action, { buffer = bufnr })
      vim.keymap.set('v', '<leader>a', require('lspsaga.codeaction').range_code_action, { buffer = bufnr })

      -- breakpoint
      vim.keymap.set('n', '<leader>tb', require('dap').toggle_breakpoint, { buffer = bufnr })
    end,
  },
})


