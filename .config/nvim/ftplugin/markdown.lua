-- Check if file is in Obsidian/docs repos
local function is_docs_repo()
  local path = vim.fn.expand "%:p:h"
  local norm_path = vim.fn.substitute(path, "/$", "", "")
  return vim.fn.match(norm_path, "^/home/decoder/dev/obsidian") ~= -1
    or vim.fn.match(norm_path, "^/home/decoder/loft/vcluster-docs") ~= -1
end

vim.keymap.set(
  "v",
  "<C-k>",
  ':lua require("user_functions.utils").bracket_link()<CR>',
  { noremap = true, silent = true, buffer = true }
)

-- markdown.nvim settings
local markdown_settings = {
  no_default_key_mappings = 1,
  folding_disabled = 0,
  folding_style_pythonic = 1,
  folding_level = 2,
  toc_autofit = 1,
  conceal = 0,
  conceal_code_blocks = 0,
  no_extensions_in_markdown = 1,
  autowrite = 1,
  follow_anchor = 1,
  auto_insert_bullets = 0,
  new_list_item_indent = 0,
}

for key, value in pairs(markdown_settings) do
  vim.g["vim_markdown_" .. key] = value
end

-- markdown-preview settings
vim.g.mkdp_browser = "/usr/bin/firefox"
vim.g.mkdp_echo_preview_url = 0

-- Setup completion
local cmp = require "cmp"
cmp.setup.buffer {
  sources = {
    { name = "luasnip", priority = 90 },
    { name = "projects" },
    { name = "spell" },
    {
      name = "buffer",
      option = {
        get_bufnrs = function()
          local bufs = {}
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            bufs[vim.api.nvim_win_get_buf(win)] = true
          end
          return vim.tbl_keys(bufs)
        end,
      },
    },
    { name = "path" },
  },
  experimental = { ghost_text = false },
}

-- FileType autocmd for markdown files
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "mdx", "mdown", "mkd", "mkdn", "mdwn" },
  callback = function()
    -- Local settings
    vim.opt_local.conceallevel = 0
    vim.bo.textwidth = is_docs_repo() and 80 or 175
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "en_us"
    vim.opt_local.expandtab = true
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 4
    vim.opt_local.autoindent = true

    -- Arrow abbreviations
    local arrows = { [">>"] = "→", ["<<"] = "←", ["^^"] = "↑", ["VV"] = "↓" }
    for key, val in pairs(arrows) do
      vim.cmd(string.format("iabbrev %s %s", key, val))
    end

    -- Handle code blocks

    -- BoldMe function for making selected text bold
    local function BoldMe()
      -- Get visual selection coordinates
      local start_pos = vim.fn.getpos "'<"
      local end_pos = vim.fn.getpos "'>"

      -- Get selected text
      local lines = vim.fn.getline(start_pos[2], end_pos[2])
      if #lines == 0 then
        return
      end

      if #lines == 1 then
        -- Single line selection
        local line = lines[1]
        local selected_text = string.sub(line, start_pos[3], end_pos[3])
        local new_text = "**" .. selected_text .. "**"
        local new_line = string.sub(line, 1, start_pos[3] - 1) .. new_text .. string.sub(line, end_pos[3] + 1)
        vim.fn.setline(start_pos[2], new_line)
      else
        -- Multi-line selection
        lines[1] = string.sub(lines[1], start_pos[3])
        lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
        local selected_text = table.concat(lines, "\n")
        local new_text = "**" .. selected_text .. "**"

        -- Replace the selection
        vim.cmd("normal! `<v`>c" .. new_text)
      end
    end

    -- Set keymaps
    local function set_keymaps()
      local maps = {
        { "n", "]]", "<Plug>Markdown_MoveToNextHeader" },
        { "n", "[[", "<Plug>Markdown_MoveToPreviousHeader" },
        { "n", "]c", "]c", { noremap = true } },
        { "n", "<leader>mp", ":MarkdownPreview<CR>:silent !bash -c 'wmctrl -a Firefox'<CR>" },
        { "n", "<leader>pi", ":call mdip#MarkdownClipboardImage()<CR>" },
        { "n", "ctd", "4wvg$y" },
        { "v", "<leader>hi", ":HeaderIncrease<CR>" },
        { "v", "<Leader>b", BoldMe, {} },
        { "x", "<Leader>b", BoldMe, {} },
        { "v", ",wl", [[c[<c-r>"]()<esc>]], { noremap = false } },
      }

      for _, map in ipairs(maps) do
        vim.keymap.set(map[1], map[2], map[3], vim.tbl_extend("force", { buffer = 0, silent = true }, map[4] or {}))
      end

      -- Code block text objects are now defined globally in codeblock_textobj.lua
      -- No need for markdown-specific version
    end

    pcall(function()
      vim.keymap.del("n", "]c", { buffer = 0 })
    end)
    set_keymaps()

    -- Obsidian keymaps (moved from deprecated mappings config)
    vim.keymap.set("n", "gf", function()
      return require("obsidian").util.gf_passthrough()
    end, { noremap = false, expr = true, buffer = true })

    vim.keymap.set("n", "<leader>ch", function()
      return require("obsidian").util.toggle_checkbox()
    end, { buffer = true })

    -- GitHub gist creation from visual selection
    vim.keymap.set("v", "<leader>cg", ":CreateGist<CR>", { buffer = true, desc = "Create GitHub gist from selection" })
  end,
})
