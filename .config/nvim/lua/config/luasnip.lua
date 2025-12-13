local ls = require "luasnip"
local types = require "luasnip.util.types"

-- Configure LuaSnip
ls.config.set_config {
  -- This tells LuaSnip to remember to keep around the last snippet.
  -- You can jump back into it even if you move outside of the selection
  history = true,

  -- This one is cool cause if you have dynamic snippets, it updates as you type!
  updateevents = "TextChanged,TextChangedI",

  -- Autosnippets:
  enable_autosnippets = true,

  -- Don't expand snippets inside other snippets
  region_check_events = "CursorMoved",

  -- Crazy highlights!!
  ext_opts = {
    [types.choiceNode] = {
      active = {
        virt_text = { { " <- Current Choice", "NonTest" } },
      },
    },
  },
}

-- Keymaps for jumping forward/backward
vim.keymap.set({ "i", "s" }, "<M-l>", function()
  if ls.expand_or_jumpable() then
    ls.expand_or_jump()
  end
end, { silent = true })

vim.keymap.set({ "i", "s" }, "<M-h>", function()
  if ls.jumpable(-1) then
    ls.jump(-1)
  end
end, { silent = true })

-- Keymaps for changing choices in choice nodes
vim.keymap.set({ "i", "s" }, "<M-j>", function()
  if ls.choice_active() then
    ls.change_choice(1)
  end
end, { silent = true })

-- Load friendly-snippets
require("luasnip.loaders.from_vscode").lazy_load {
  exclude = { "vim-vsnip", "tree-sitter-just", "gitcommit" },
}

-- Load our custom converted snippets
require("luasnip.loaders.from_lua").lazy_load { paths = vim.fn.stdpath "config" .. "/lua/snippets" }

-- Command to edit snippets for current filetype
vim.api.nvim_create_user_command("LuaSnipEdit", function()
  local ft = vim.bo.filetype
  local snippets_dir = vim.fn.stdpath "config" .. "/lua/snippets"
  local snippet_file = snippets_dir .. "/" .. ft .. ".lua"

  -- Create the file if it doesn't exist
  if vim.fn.filereadable(snippet_file) == 0 then
    local template = [[local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- Add your snippets here
}]]
    vim.fn.writefile(vim.split(template, "\n"), snippet_file)
  end

  vim.cmd("edit " .. snippet_file)
end, { desc = "Edit snippets for current filetype" })

-- Command to reload snippets
vim.api.nvim_create_user_command("LuaSnipReload", function()
  require("luasnip.loaders.from_lua").load { paths = vim.fn.stdpath "config" .. "/lua/snippets" }
  vim.notify "LuaSnip snippets reloaded!"
end, { desc = "Reload LuaSnip snippets" })

-- Load debug commands for troubleshooting (commented out for now)
-- require("config.debug_snippets")
