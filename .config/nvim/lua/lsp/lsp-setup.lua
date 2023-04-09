-- Plugin configuration
-- LSP and LS Installer
require('lspconfig')
require('nvim-dap-virtual-text').setup()

local on_attach = function(_, bufnr)
  -- NOTE: Remember that lua is a real programming language, and as such it is possible
  -- to define small helper and utility functions so you don't have to repeat yourself
  -- many times.
  --
  -- In this case, we create a function that lets us more easily define mappings specific
  -- for LSP related items. It sets the mode, buffer and description for us each time.
  local nmap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  nmap('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
  nmap('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

  nmap('gd', vim.lsp.buf.definition, '[G]oto [D]efinition')
  nmap('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
  nmap('gI', vim.lsp.buf.implementation, '[G]oto [I]mplementation')
  nmap('<leader>D', vim.lsp.buf.type_definition, 'Type [D]efinition')
  nmap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
  nmap('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

  -- See `:help K` for why this keymap
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  nmap('<C-k>', vim.lsp.buf.signature_help, 'Signature Documentation')

  nmap('[g', ':Lspsaga diagnostic_jump_prev<CR>', 'Hover Documentation')
  -- buf_set_keymap('n', '[g', ':Lspsaga diagnostic_jump_prev<CR>', opts)
  -- buf_set_keymap('n', ']g', ':Lspsaga diagnostic_jump_next<CR>', opts)
  -- Lesser used LSP functionality
  nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
  nmap('<leader>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
  nmap('<leader>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
  nmap('<leader>wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, '[W]orkspace [L]ist Folders')

  -- Create a command `:Format` local to the LSP buffer
  vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
    vim.lsp.buf.format()
  end, { desc = 'Format current buffer with LSP' })
end

-- require "lsp_signature".on_attach({
      -- bind = true, -- This is mandatory, otherwise border config won't get registered.
      -- handler_opts = {
        -- border = "rounded"
      -- }
    -- }, bufnr)
  -- -- ======================= The Keymaps =========================
  -- -- jump to definition
  -- buf_set_keymap('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)

  -- -- Format buffer
  -- buf_set_keymap('n', '<c-f>', '<cmd>lua vim.lsp.buf.format({ async = true })<CR>', opts)
  -- buf_set_keymap('n', 'dm', '<cmd>lua vim.lsp.buf.document_symbol()<CR>', opts)

  -- -- Jump LSP diagnostics
  -- -- NOTE: Currently, there is a bug in lspsaga.diagnostic module. Thus we use
  -- --       Vim commands to move through diagnostics.
  -- buf_set_keymap('n', '[g', ':Lspsaga diagnostic_jump_prev<CR>', opts)
  -- buf_set_keymap('n', ']g', ':Lspsaga diagnostic_jump_next<CR>', opts)

  -- -- Rename symbol
  -- buf_set_keymap('n', '<leader>rn', "<cmd>lua require('lspsaga.rename').rename()<CR>", opts)

  -- -- Go to implementation
  -- buf_set_keymap('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<CR>', opts)

  -- -- Find reference
  -- buf_set_keymap('n', 'gr', '<cmd>lua require("lspsaga.provider").lsp_finder()<CR>', opts)

  -- -- Doc popup scrolling
  -- buf_set_keymap('n', 'K', "<cmd>lua require('lspsaga.hover').render_hover_doc()<CR>", opts)

  -- -- codeaction
  -- buf_set_keymap('n', '<leader>ac', "<cmd>lua require('lspsaga.codeaction').code_action()<CR>", opts)
  -- buf_set_keymap('v', '<leader>a', ":<C-U>lua require('lspsaga.codeaction').range_code_action()<CR>", opts)

  -- -- breakpoint
  -- buf_set_keymap('n', '<leader>tb', "<cmd>lua require('dap').toggle_breakpoint()<CR>", opts)
  -- buf_set_keymap('n', '<leader>ds', ":Telescope lsp_document_symbols<CR>", opts)

  -- -- Floating terminal
  -- -- NOTE: Use `vim.cmd` since `buf_set_keymap` is not working with `tnoremap...`
  -- vim.cmd [[
  -- nnoremap <silent> <A-d> <cmd>lua require('lspsaga.floaterm').open_float_terminal()<CR>
  -- nnoremap <silent> ga    <cmd>lua vim.lsp.buf.code_action()<CR>
  -- tnoremap <silent> <A-d> <C-\><C-n>:lua require('lspsaga.floaterm').close_float_terminal()<CR>
  -- ]]
-- end

require('go').setup({
  on_attach = on_attach
})
local lspconfig = require 'lspconfig'
lspconfig.pyright.setup {}
lspconfig.lua_ls.setup {
      settings = {
        Lua = {
            diagnostics = {
                globals = { 'vim' }
            }
        }
    }
}

local configs = require 'lspconfig.configs'
-- Check if it's already defined for when reloading this file.
configs.up = {
  default_config = {
    cmd = { "up", "xpls", "serve" };
    filetypes = { 'yaml' };
    root_dir = lspconfig.util.root_pattern('crossplane.yaml')
  };
}

require("lspconfig")['up'].setup({
  lsp_on_attach = true
})

local server_specific_opts = {
  sumneko_lua = function(opts)
    opts.settings = {
      Lua = {
        -- NOTE: This is required for expansion of lua function signatures!
        completion = { callSnippet = "Replace" },
        diagnostics = {
          globals = { 'vim' },
        },
      },
    }
  end,

  html = function(opts)
    opts.filetypes = { "html", "htmldjango" }
  end,
}

-- `nvim-cmp` comes with additional capabilities, alongside the ones
-- provided by Neovim!
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').default_capabilities()

lspconfig.gopls.setup{
	cmd = {'gopls'},
	-- for postfix snippets and analyzers
	capabilities = capabilities,
	    settings = {
	      gopls = {
		      experimentalPostfixCompletions = true,
		      analyses = {
		        unusedparams = true,
		        shadow = true,
		     },
		     staticcheck = true,
		    },
	    },
	on_attach = on_attach,
}

