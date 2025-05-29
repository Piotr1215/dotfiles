local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local c = ls.choice_node
local fmt = require("luasnip.extras.fmt").fmt
local rep = require("luasnip.extras").rep

return {
  -- Snippet for import statement
  s("im", {
    t("import \""), i(1, "package"), t("\"")
  }),

  -- Snippet for a import block
  s("ims", {
    t({"import (", "\t\""}), i(1, "package"), t({"\"", ")"})
  }),

  -- Snippet for a constant
  s("co", {
    t("const "), i(1, "name"), t(" = "), i(2, "value")
  }),

  -- Snippet for a type interface
  s("tyi", {
    t({"type "}), i(1, "name"), t({" interface {", "\t"}), i(0), t({"", "}"})
  }),

  -- Snippet for a struct declaration
  s("tys", {
    t("type "), i(1, "name"), t({" struct {", "\t"}), i(0), t({"", "}"})
  }),

  -- Snippet for function declaration
  s("func", {
    t("func "), i(1), t("("), i(2), t(") "), i(3), t({" {", "\t"}), i(0), t({"", "}"})
  }),

  -- Snippet for if err != nil
  s("iferr", {
    t({"if err != nil {", "\treturn "}), i(1, "nil, "), i(2, "err"), t({"", "}"})
  }),

  -- Snippet for fmt.Println()
  s("fp", {
    t("fmt.Println(\""), i(1), t("\")")
  }),

  -- Snippet for log.Printf() with variable content
  s("lv", {
    t("log.Printf(\""), i(1, "var"), t(": %#+v\\n\", "), rep(1), t(")")
  }),

  -- Snippet for a for loop using fmt
  s("for", fmt([[
for {} := {}; {} < {}; {}++ {{
	{}
}}]], {
    i(1, "i"),
    i(2, "0"),
    rep(1),
    i(3, "count"),
    rep(1),
    i(0)
  })),

  -- Snippet for Test function
  s("tf", {
    t("func Test"), i(1), t("(t *testing.T) {\n\t"), i(0), t("\n}")
  }),

  -- Snippet for Benchmark function
  s("bf", fmt([[
func Benchmark{}(b *testing.B) {{
	for {} := 0; {} < b.N; {}++ {{
		{}
	}}
}}]], {
    i(1),
    i(2, "i"),
    rep(2),
    rep(2),
    i(0)
  }))
}