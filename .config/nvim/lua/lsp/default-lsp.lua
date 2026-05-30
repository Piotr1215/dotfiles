local M = {}

M.capabilities = require("cmp_nvim_lsp").default_capabilities()
vim.lsp.log.set_level "warn" -- change to "debug" for more info

-- 0.12: LSP jump funcs (definition/declaration/type_definition/implementation)
-- honour 'switchbuf'. Reuse an already-open window for the target buffer instead
-- of always splitting, so stock `gd`/`grt`/etc. land in the existing view.
vim.o.switchbuf = "useopen,uselast"

-- The on_attach function is now deprecated - keymaps should be set via LspAttach autocmd
-- Keeping this for backward compatibility with rust-tools which still uses it
M.on_attach = function(_, _)
  -- This function is kept for backward compatibility
  -- All keymaps have been moved to LspAttach autocmd below
end

-- Set up LSP keymaps via LspAttach autocmd (new recommended approach)
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
  callback = function(args)
    local bufnr = args.buf
    local client = vim.lsp.get_client_by_id(args.data.client_id)

    -- Skip certain clients if needed
    if not client then
      return
    end

    local nmap = function(keys, func, desc)
      if desc then
        desc = "LSP: " .. desc
      end
      vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
    end

    vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"
    vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { buffer = bufnr, desc = "Go to previous diagnostic message" })
    vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { buffer = bufnr, desc = "Go to next diagnostic message" })
    vim.keymap.set("i", "<C-k>", vim.lsp.buf.signature_help, { buffer = bufnr })
    nmap("K", vim.lsp.buf.hover, "Hover Documentation")

    nmap("<leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")
    nmap("gd", vim.lsp.buf.definition, "[G]oto [D]efinition")
    -- 0.12: LSP jump funcs honour 'switchbuf' (set in this file) so gd reuses an
    -- existing window. gD forces definition into a fresh vsplit — done via on_list
    -- because 'switchbuf=useopen' would otherwise hijack a plain `:vsplit | definition`
    -- jump back into the existing window, leaving the split empty.
    nmap("gD", function()
      vim.lsp.buf.definition {
        on_list = function(result)
          local item = result.items[1]
          if not item then
            return
          end
          vim.cmd("vsplit " .. vim.fn.fnameescape(item.filename))
          vim.api.nvim_win_set_cursor(0, { item.lnum, math.max(item.col - 1, 0) })
        end,
      }
    end, "Definition in vsplit")
    nmap("gI", vim.lsp.buf.implementation, "[G]oto [I]mplementation")
    nmap("<leader>Ic", vim.lsp.buf.incoming_calls, "[I]ncoming [C]alls")
    nmap("<leader>Oc", vim.lsp.buf.outgoing_calls, "[O]utgoing [C]alls")
    -- Use Neovim's default grr for references, removing custom gr mapping
    nmap("<leader>rn", vim.lsp.buf.rename, "Rename Symbol")
    -- <leader>D retired: 0.12 ships stock `grt` for type_definition

    nmap("<leader>ds", require("telescope.builtin").lsp_document_symbols, "[D]ocument [S]ymbols")
    nmap("<leader>ws", require("telescope.builtin").lsp_dynamic_workspace_symbols, "[W]orkspace [S]ymbols")

    -- Lesser used LSP functionality
    nmap("<leader>wA", vim.lsp.buf.add_workspace_folder, "[W]orkspace [A]dd Folder")
    nmap("<leader>wr", vim.lsp.buf.remove_workspace_folder, "[W]orkspace [R]emove Folder")
    nmap("<leader>wl", function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, "[W]orkspace [L]ist Folders")

    nmap("<c-f>", vim.lsp.buf.format, "Format Buffer")

    nmap("<leader>br", require("dap").toggle_breakpoint, "Toggle Breakpoint")
  end,
})

return M
