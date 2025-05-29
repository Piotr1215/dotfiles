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
  -- Template for Python hook script
  s("hook", {
    t({
      "#!/usr/bin/env python3",
      "import sys",
      "import json",
      "",
      "def main():",
      "    try:",
      "        # Read the 'before' and 'after' task JSON from stdin",
      "        before_json = sys.stdin.readline()",
      "        after_json = sys.stdin.readline()",
      "        ",
      "        # Parse JSON data",
      "        before = json.loads(before_json)",
      "        after = json.loads(after_json)",
      "        "
    }), i(0)
  }),

}