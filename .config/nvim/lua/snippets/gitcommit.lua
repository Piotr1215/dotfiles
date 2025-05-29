local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node

return {
  -- Conventional commit templates
  s("cc", {
    i(1, "type"), t("("), i(2, "scope"), t("): "), i(3, "title"), t({"", "", ""}), i(0)
  }),

  s("commitfix", {
    t("fix("), i(1, "scope"), t("): "), i(2, "title"), t({"", "", ""}), i(0)
  }),

  s("commitfeat", {
    t("feat("), i(1, "scope"), t("): "), i(2, "title"), t({"", "", ""}), i(0)
  }),

  s("commitbuild", {
    t("build("), i(1, "scope"), t("): "), i(2, "title"), t({"", "", ""}), i(0)
  }),

  s("commitchore", {
    t("chore("), i(1, "scope"), t("): "), i(2, "title"), t({"", "", ""}), i(0)
  }),

  s("commitci", {
    t("ci("), i(1, "scope"), t("): "), i(2, "title"), t({"", "", ""}), i(0)
  }),

  s("commitdocs", {
    t("docs("), i(1, "scope"), t("): "), i(2, "title"), t({"", "", ""}), i(0)
  }),

  s("commitstyle", {
    t("style("), i(1, "scope"), t("): "), i(2, "title"), t({"", "", ""}), i(0)
  }),

  s("commitrefactor", {
    t("refactor("), i(1, "scope"), t("): "), i(2, "title"), t({"", "", ""}), i(0)
  }),

  s("commitperf", {
    t("perf("), i(1, "scope"), t("): "), i(2, "title"), t({"", "", ""}), i(0)
  }),

  s("commitest", {
    t("test("), i(1, "scope"), t("): "), i(2, "title"), t({"", "", ""}), i(0)
  }),

  s("BREAK", {
    t("BREAKING CHANGE: "), i(0)
  })
}