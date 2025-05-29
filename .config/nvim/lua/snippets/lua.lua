local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local r = ls.restore_node
local sn = ls.snippet_node
local fmt = require("luasnip.extras.fmt").fmt
local fmta = require("luasnip.extras.fmt").fmta

return {
  s("keymap", {
    t("vim.keymap.set('n','<leader>"), i(1), t("', '"), i(2), t("', { remap = true, silent = false })")
  }),

  -- Create a basic Lua module
  s("mod", {
    t("local "), i(1, "M"), t({" = {}", "", "", "return "}), i(1, "M")
  }),

  -- Create a function for Lua module
  s("mfunc", {
    t("function M."), i(1, "function_name"), t("("), i(2, "params"), t({") ", "	"}), i(0), t({"", "end"})
  }),

}