-- nvim-cmp
local lspkind = require "lspkind"
local cmp = require "cmp"
local luasnip = require "luasnip"

local has_words_before = function()
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match "%s" == nil
end

local feedkey = function(key, mode)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), mode, true)
end

cmp.setup {
  snippet = {
    expand = function(args)
      require("luasnip").lsp_expand(args.body)
    end,
  },
  
  completion = {
    completeopt = "menu,menuone,noselect",
  },

  formatting = {
    expandable_indicator = true,
    fields = {
      "abbr",
      "kind",
      "menu",
    },
    format = lspkind.cmp_format {
      mode = "symbol_text", -- Use "symbol" to only show the icon or "symbol_text" for both icon and text
      maxwidth = 50, -- Optional, for max width of the displayed item
      ellipsis_char = "...", -- Optional, truncate the item if it's too long
      menu = {
        buffer = "[Buffer]",
        nvim_lsp = "[LSP]",
        nvim_lua = "[Lua]",
        projects = "[Projects]",
        emoji = "[Emoji]",
        luasnip = "[Snippet]",
      },
    },
  },

  mapping = {
    ["<C-p>"] = cmp.mapping.select_prev_item(),
    ["<C-n>"] = cmp.mapping.select_next_item(),
    ["<C-d>"] = cmp.mapping.scroll_docs(-4),
    ["<C-f>"] = cmp.mapping.scroll_docs(4),
    ["<C-Space>"] = cmp.mapping.complete(),
    ["<C-e>"] = cmp.mapping.close(),
    ["<CR>"] = cmp.mapping.confirm {
      behavior = cmp.ConfirmBehavior.Replace,
      select = true,
    },

    ["<Tab>"] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      elseif require("luasnip").expand_or_jumpable() then
        require("luasnip").expand_or_jump()
      elseif has_words_before() then
        cmp.complete()
      else
        fallback()
      end
    end, { "i", "s" }),

    ["<S-Tab>"] = cmp.mapping(function()
      if cmp.visible() then
        cmp.select_prev_item()
      elseif require("luasnip").jumpable(-1) then
        require("luasnip").jump(-1)
      end
    end, { "i", "s" }),
  },

  sources = cmp.config.sources({
    { name = "nvim_lsp" },
    { name = "nvim_lua", priority = 100 },
    { name = "luasnip", priority = 90 },
    { name = "path" },
  }, {
    { name = "buffer" },
    { name = "emoji" },
    { name = "crates" },
    { name = "projects", priority = 100 },
  }),
}

-- Disable cmp for `/` search mode (cleaner for remote operators and native search)
-- Commenting out to use native search without completion popup
-- cmp.setup.cmdline("/", {
--   sources = {
--     { name = "buffer" },
--   },
-- })

-- Use cmdline & path source for ':'
cmp.setup.cmdline(":", {
  mapping = cmp.mapping.preset.cmdline({
    ['<Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      else
        fallback()
      end
    end, { 'c' }),
    ['<S-Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_prev_item()
      else
        fallback()
      end
    end, { 'c' }),
  }),
  sources = cmp.config.sources({
    { name = "path" },
  }, {
    { name = "cmdline" },
  }),
  window = {
    completion = cmp.config.window.bordered({
      winhighlight = "Normal:Pmenu,FloatBorder:Pmenu,Search:None",
      col_offset = 5,  -- Move it 5 columns to the right to uncover line numbers (even with 4-digit line numbers)
      side_padding = 1,
      max_height = 8,  -- Limit the height to show fewer items
    }),
  },
  view = {
    entries = { name = 'custom', selection_order = 'near_cursor' }
  },
})

local highlight = {
  "CursorColumn",
}
require("ibl").setup {
  indent = { highlight = highlight, char = "" },
  whitespace = {
    remove_blankline_trail = false,
  },
  scope = { enabled = false },
}
