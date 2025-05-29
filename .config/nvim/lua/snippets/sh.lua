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
  -- Strict mode for bash script
  s("start", {
    t({
      "#!/usr/bin/env bash",
      "",
      "set -eo pipefail",
      "",
      "# Add source and line number when running in debug mode: __run_with_xtrace.sh $TM_FILENAME",
      "# Set new line and tab for word splitting",
      "IFS=$'\\n\\t'",
      "",
      ""
    })
  }),

  -- Read file line by line
  s("while_file", {
    t({
      "while IFS= read -r line; do",
      "",
      "    echo \"$line\"",
      "",
      "done </"
    }), i(0)
  }),

}