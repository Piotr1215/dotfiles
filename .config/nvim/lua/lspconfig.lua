-- Plugin configuration
-- LSP and LS Installer
local lsp_installer = require("nvim-lsp-installer")

-- The required servers
local servers = {
  "bashls",
  "sumneko_lua",
  "dockerls",
  "gopls",
  "grammarly",
  "jsonls",
  "html",
  "vimls",
  "jsonnet_ls",
  "prosemd_lsp",
  "taplo",
  "yamlls",
  "emmet_ls",
}
local lspkind = require "lspkind"
local cmp = require "cmp"

local has_words_before = function()
    local line, col = unpack(vim.api.nvim_win_get_cursor(0))
    return col ~= 0
        and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]
                :sub(col, col)
                :match "%s"
            == nil
end

local feedkey = function(key, mode)
    vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes(key, true, true, true),
        mode,
        true
    )
end

-- Fancy Autocompletion popup icons {{{3
local CMP_KINDS = {
    Class = "ﴯ",
    Color = "",
    Constant = "",
    Constructor = "",
    Enum = "",
    EnumMember = "",
    Event = "",
    Field = "ﰠ",
    File = "",
    Folder = "",
    Function = "",
    Interface = "",
    Keyword = "",
    Method = "",
    Module = "",
    Operator = "",
    Property = "ﰠ",
    Reference = "",
    Snippet = "",
    Struct = "פּ",
    Text = "",
    TypeParameter = "",
    Unit = "塞",
    Value = "",
    Variable = "",
}
-- 3}}}

cmp.setup({
    formatting = {
        format = lspkind.cmp_format({
            mode = "symbol_text",
            preset = "codicons",
            symbol_map = CMP_KINDS,
            menu = {
                buffer = "[Buffer]",
                nvim_lsp = "[LSP]",
                luasnip = "[LuaSnip]",
                nvim_lua = "[Lua]",
                latex_symbols = "[Latex]",
            },
        }),
    },
    snippet = {
        expand = function(args)
            vim.fn["vsnip#anonymous"](args.body)
        end,
    },
    mapping = cmp.mapping.preset.insert({
        ["<C-b>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),
        ["<C-Space>"] = cmp.mapping.complete(),
        ["<C-e>"] = cmp.mapping.abort(),
        ["<CR>"] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Replace,
            select = true,
        }),
        ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
                cmp.select_next_item()
            elseif vim.fn["vsnip#available"](1) == 1 then
                feedkey("<Plug>(vsnip-expand-or-jump)", "")
            elseif has_words_before() then
                cmp.complete()
            else
                fallback() -- The fallback function sends a already mapped key. In this case, it's probably `<Tab>`.
            end
        end, { "i", "s" }),
        ["<S-Tab>"] = cmp.mapping(function()
            if cmp.visible() then
                cmp.select_prev_item()
            elseif vim.fn["vsnip#jumpable"](-1) == 1 then
                feedkey("<Plug>(vsnip-jump-prev)", "")
            end
        end, { "i", "s" }),
    }),
    sources = cmp.config.sources({
        { name = "vsnip" },
        { name = "nvim_lsp" },
        { name = "cmp_tabnine" },
    }, {
        { name = "buffer" },
    }),
})

-- Use buffer source for `/` (if you enabled `native_menu`, this won't work anymore).
cmp.setup.cmdline("/", {
    mapping = cmp.mapping.preset.cmdline(),
    sources = {
        { name = "buffer" },
    },
})

-- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
cmp.setup.cmdline(":", {
    mapping = cmp.mapping.preset.cmdline(),
    sources = cmp.config.sources({
        { name = "path" },
    }, {
        { name = "cmdline" },
    }),
})
-- 2}}}
local lsp_installer = require "nvim-lsp-installer"
lsp_installer.setup({ ensure_installed = SERVERS })
local lspconfig = require "lspconfig"

-- Set up keymaps {{{3
local on_attach = function(_, bufnr)
    local opts = { noremap = true, silent = true, buffer = bufnr }

    -- Lspsaga based config
    vim.keymap.set("n", "<leader>rn", require("lspsaga.rename").rename, opts)
    vim.keymap.set("n", "gr", require("lspsaga.provider").lsp_finder, opts)
    vim.keymap.set("n", "]g", ":Lspsaga diagnostic_jump_next<CR>", opts)
    vim.keymap.set("n", "[g", ":Lspsaga diagnostic_jump_prev<CR>", opts)
    vim.keymap.set("n", "K", require("lspsaga.hover").render_hover_doc, opts)
    vim.keymap.set("n", "<C-F>", function()
        require("lspsaga.action").smart_scroll_with_saga(1)
    end, opts)
    vim.keymap.set("n", "<C-B>", function()
        require("lspsaga.action").smart_scroll_with_saga(-1)
    end, opts)
    vim.keymap.set(
        "n",
        "gD",
        require("lspsaga.provider").preview_definition,
        opts
    )
    vim.keymap.set(
        "n",
        "<leader>ca",
        require("lspsaga.codeaction").code_action,
        opts
    )
    vim.keymap.set(
        "v",
        "<leader>ca",
        ':<C-U>lua require("lspsaga.codeaction").range_code_action()<CR>',
        opts
    )

    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
    vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
    vim.keymap.set("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, opts)
    vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)
    vim.keymap.set(
        "n",
        "<leader>wr",
        vim.lsp.buf.remove_workspace_folder,
        opts
    )
    vim.keymap.set("n", "<leader>wl", function()
        vim.inspect(vim.lsp.buf.list_workspace_folders())
    end, opts)
    vim.api.nvim_create_user_command("Format", vim.lsp.buf.formatting, {})
end
-- 3}}}

-- server-specific options {{{3
local SERVER_SPECIFIC_OPTS = {
    clangd = function(opts)
        opts.cmd = {
            "clangd",
            "--clang-tidy",
        }
    end,
    pylsp = function(opts)
        opts.settings = {
            pylsp = {
                -- configurationSources = {"flake8"},
                plugins = {
                    jedi_completion = { include_params = true },
                    flake8 = { enabled = true },
                    pycodestyle = { enabled = false },
                },
            },
        }
    end,
    sumneko_lua = function(opts)
        opts.settings = {
            Lua = {
                -- NOTE: This is required for expansion of lua function signatures!
                runtime = { version = "LuaJIT" },
                workspace = {
                    library = vim.api.nvim_get_runtime_file("", true),
                },
                completion = { callSnippet = "Replace" },
                diagnostics = {
                    globals = { "vim", "P" },
                },
            },
        }
    end,
    html = function(opts)
        opts.filetypes = { "html", "htmldjango" }
    end,
}
-- 3}}}

-- nvim-cmp supports additional completion capabilities
local capabilities = require("cmp_nvim_lsp").update_capabilities(
    vim.lsp.protocol.make_client_capabilities()
)

for _, server in ipairs(SERVERS) do
    local opts = {
        on_attach = on_attach,
        -- flags = { debounce_text_changes = 150 },
        capabilities = capabilities,
    }

    if SERVER_SPECIFIC_OPTS[server] then
        SERVER_SPECIFIC_OPTS[server](opts)
    end

    lspconfig[server].setup(opts)
end
-- 2}}}

-- lspsaga
require("lspsaga").init_lsp_saga({
    finder_action_keys = {
        open = "<CR>",
        quit = { "q", "<esc>" },
    },
    code_action_keys = {
        quit = { "q", "<esc>" },
    },
    rename_action_keys = {
        quit = "<esc>",
    },
})

-- Lualine
require("lualine").setup({
    sections = {
        lualine_c = {
            { "filename", path = 1 },
            "lsp_progress",
        },
    },
})

-- indent-blankline
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
        "python",
        "rust",
        "c",
        "cpp",
        "bash",
        "go",
        "html",
        "toml",
    },
    highlight = {
        enable = true,
    },
})

-- Tagbar
vim.cmd [[
nmap <F8> :TagbarOpenAutoClose<CR>
]]

-- FZF
vim.cmd [[
nnoremap <C-P> :Files<CR>
nnoremap <Tab> :GFiles<CR>
nnoremap <C-H> :GFiles?<CR>
nnoremap <C-K> :BLines<CR>
if executable('rg')
    nnoremap <C-G> :Rg<CR>
else
    echom "Ripgrep (rg) is missing. Please install Ripgrep"
endif
]]

-- auto-pairs-gentle
vim.g.AutoPairs = {
    ["("] = ")",
    ["["] = "]",
    ["{"] = "}",
    ["'"] = "'",
    ['"'] = '"',
    ["`"] = "`",
    -- ['<']='>',
}

-- vim-markdown
vim.g.vim_markdown_folding_disabled = true

-- vim-autoformat
vim.cmd [[
nnoremap <F3> :Autoformat<CR> :w<CR>
]]

-- markdown-preview
vim.cmd [[
nnoremap <M-m> :MarkdownPreviewToggle<CR>
]]

-- vim-python-pep8-indent
vim.g.python_pep8_indent_multiline_string = -1

-- vim-easy-align
vim.cmd [[
xmap ga <Plug>(EasyAlign)
nmap ga <Plug>(EasyAlign)
]]
-- 1}}}
