-- Plugin configuration
-- LSP and LS Installer
require('lspconfig')
local dap, dapui = require("dap"), require("dapui")
require('nvim-dap-virtual-text').setup()
require('dap-go').setup()
require("dapui").setup()
  require "lsp_signature".setup({
    bind = true, -- This is mandatory, otherwise border config won't get registered.
    handler_opts = {
      border = "rounded"
    }
  })
local on_attach = function(_, bufnr)
  -- Create some shortcut functions.
  -- NOTE: The `vim` variable is supplied by Neovim.
  if vim.bo[bufnr].buftype ~= "" or vim.bo[bufnr].filetype == "helm" then
    vim.diagnostic.disable()
  end

  local function buf_set_keymap(...)
    vim.api.nvim_buf_set_keymap(bufnr, ...)
  end

  local function buf_set_option(...)
    vim.api.nvim_buf_set_option(bufnr, ...)
  end

  -- Enable completion triggered by <c-x><c-o>
  buf_set_option('omnifunc', 'v:lua.vim.lsp.omnifunc')

  local opts = { noremap = true, silent = true }
require "lsp_signature".on_attach({
      bind = true, -- This is mandatory, otherwise border config won't get registered.
      handler_opts = {
        border = "rounded"
      }
    }, bufnr)
  -- ======================= The Keymaps =========================
  -- jump to definition
  buf_set_keymap('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)

  -- Format buffer
  buf_set_keymap('n', '<c-f>', '<cmd>lua vim.lsp.buf.format({ async = true })<CR>', opts)
  buf_set_keymap('n', 'dm', '<cmd>lua vim.lsp.buf.document_symbol()<CR>', opts)

  -- Jump LSP diagnostics
  -- NOTE: Currently, there is a bug in lspsaga.diagnostic module. Thus we use
  --       Vim commands to move through diagnostics.
  buf_set_keymap('n', '[g', ':Lspsaga diagnostic_jump_prev<CR>', opts)
  buf_set_keymap('n', ']g', ':Lspsaga diagnostic_jump_next<CR>', opts)

  -- Rename symbol
  buf_set_keymap('n', '<leader>rn', "<cmd>lua require('lspsaga.rename').rename()<CR>", opts)

  -- Go to implementation
  buf_set_keymap('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<CR>', opts)

  -- Find reference
  buf_set_keymap('n', 'gr', '<cmd>lua require("lspsaga.provider").lsp_finder()<CR>', opts)

  -- Doc popup scrolling
  buf_set_keymap('n', 'K', "<cmd>lua require('lspsaga.hover').render_hover_doc()<CR>", opts)

  -- codeaction
  buf_set_keymap('n', '<leader>ac', "<cmd>lua require('lspsaga.codeaction').code_action()<CR>", opts)
  buf_set_keymap('v', '<leader>a', ":<C-U>lua require('lspsaga.codeaction').range_code_action()<CR>", opts)

  -- breakpoint
  buf_set_keymap('n', '<leader>tb', "<cmd>lua require('dap').toggle_breakpoint()<CR>", opts)
  buf_set_keymap('n', '<leader>ds', ":Telescope lsp_document_symbols<CR>", opts)

  -- Floating terminal
  -- NOTE: Use `vim.cmd` since `buf_set_keymap` is not working with `tnoremap...`
  vim.cmd [[
  nnoremap <silent> <A-d> <cmd>lua require('lspsaga.floaterm').open_float_terminal()<CR>
  nnoremap <silent> ga    <cmd>lua vim.lsp.buf.code_action()<CR>
  tnoremap <silent> <A-d> <C-\><C-n>:lua require('lspsaga.floaterm').close_float_terminal()<CR>
  ]]
end

require('go').setup({
  on_attach = on_attach
})
local lspconfig = require 'lspconfig'
lspconfig.pyright.setup {}
lspconfig.lua_ls.setup {}
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

-- nvim-cmp
local lspkind = require('lspkind')
local cmp = require("cmp")

local has_words_before = function()
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

local feedkey = function(key, mode)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), mode, true)
end

local cmp_kinds = {
  Text = "",
  Method = "",
  Function = "",
  Constructor = "",
  Field = "ﰠ",
  Variable = "",
  Class = "ﴯ",
  Interface = "",
  Module = "",
  Property = "ﰠ",
  Unit = "塞",
  Value = "",
  Enum = "",
  Keyword = "",
  Snippet = "",
  Color = "",
  File = "",
  Reference = "",
  Folder = "",
  EnumMember = "",
  Constant = "",
  Struct = "פּ",
  Event = "",
  Operator = "",
  TypeParameter = "",
}

cmp.setup({
  snippet = {
    expand = function(args)
      vim.fn["vsnip#anonymous"](args.body)
    end,
  },

  formatting = {
    format = lspkind.cmp_format({
      preset = 'codicons',
      symbol_map = cmp_kinds, -- The glyphs will be used by `lspkind`
      async = true,
      menu = ({
        buffer = "[Buffer]",
        nvim_lsp = "[LSP]",
        luasnip = "[LuaSnip]",
        nvim_lua = "[Lua]",
        latex_symbols = "[Latex]",
      }),
    }),
  },

  mapping = {
    ['<C-p>'] = cmp.mapping.select_prev_item(),
    ['<C-n>'] = cmp.mapping.select_next_item(),
    ['<C-d>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<C-e>'] = cmp.mapping.close(),
    ['<CR>'] = cmp.mapping.confirm {
      behavior = cmp.ConfirmBehavior.Replace,
      select = true,
    },

    -- Use Ctrl + j and Shift-Ctrl + j to browse through the suggestions.
    ["<Tab>"] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      elseif vim.fn["vsnip#available"](1) == 1 then
        feedkey("<Plug>(vsnip-expand-or-jump)", "")
      elseif has_words_before() then
        cmp.complete()
      else
        fallback()
      end
    end, { "i", "s" }),

    ["<S-Tab>"] = cmp.mapping(function()
      if cmp.visible() then
        cmp.select_prev_item()
      elseif vim.fn["vsnip#jumpable"](-1) == 1 then
        feedkey("<Plug>(vsnip-jump-prev)", "")
      end
    end, { "i", "s" }),
  },

  sources = {
    { name = 'nvim_lsp' },
    { name = 'nvim_lua' },
    { name = 'vsnip' },
    { name = 'buffer' },
    { name = 'emoji' },
    { name = 'path' },
    { name = "crates" },
  },
})

-- Use buffer source for `/`
cmp.setup.cmdline('/', {
  sources = {
    { name = 'buffer' }
  }
})

-- Use cmdline & path source for ':'
cmp.setup.cmdline(':', {
  sources = cmp.config.sources({
    { name = 'path' }
  }, {
    { name = 'cmdline' }
  })
})

-- Indent-blankline
require("indent_blankline").setup({
  -- for example, context is off by default, use this to turn it on
  space_char_blankline = " ",
  show_current_context = true,
  show_current_context_start = true,
  filetype_exclude = { "help", "packer" },
  buftype_exclude = { "terminal", "nofile" },
  show_trailing_blankline_indent = false,
})

-- treesitter
require("nvim-treesitter.configs").setup({
  ensure_installed = {
    "c",
    "cpp",
    "bash",
    "go",
    "html",
    "yaml",
    "toml",
    "rust",
  },
  highlight = {
    enable = true,
  },
})
require 'packer'.startup(function()
  use "mfussenegger/nvim-dap"
end)


dap.adapters.dockerfile = {
  type = 'executable';
  command = 'buildg';
  args = { 'dap', "serve" };
}

dap.adapters.lldb = {
  type = "executable",
  command = "/usr/bin/lldb-vscode", -- adjust as needed
  -- command = "/usr/bin/rust-lldb", -- adjust as needed
  name = "lldb",
}

dap.configurations.rust = {
  {
    name = "Launch",
    type = "lldb",
    request = "launch",
    program = function()
      return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
    end,
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
    args = {},
    runInTerminal = false,
  },
}
dap.configurations.dockerfile = {
  {
    type = "dockerfile",
    name = "Dockerfile Configuration",
    request = "launch",
    stopOnEntry = true,
    program = "${file}",
  },
}

dap.listeners.after.event_initialized["dapui_config"] = function()
  dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"] = function()
  dapui.close()
end
dap.listeners.before.event_exited["dapui_config"] = function()
  dapui.close()
end
dap.configurations.go = {
  {
    type = 'go';
    name = 'Debug';
    request = 'launch';
    showLog = false;
    program = "${file}";
    dlvToolPath = vim.fn.exepath('~/go/bin/dlv') -- Adjust to where delve is installed
  },
}
-- load snippets from path/of/your/nvim/config/my-cool-snippets
require("luasnip.loaders.from_vscode").lazy_load()
local null_ls = require("null-ls")

null_ls.setup({
  on_attach = function(client, bufnr)
    if client.server_capabilities.documentFormattingProvider then
      vim.cmd("nnoremap <silent><buffer> <Leader>f :lua vim.lsp.buf.formatting()<CR>")

      -- format on save
      vim.cmd("autocmd BufWritePost <buffer> lua vim.lsp.buf.formatting()")
    end

    if client.server_capabilities.documentRangeFormattingProvider then
      vim.cmd("xnoremap <silent><buffer> <Leader>f :lua vim.lsp.buf.range_formatting({})<CR>")
    end
  end,
})
