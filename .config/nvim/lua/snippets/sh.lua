local ls = require "luasnip"
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
local postfix = require("luasnip.extras.postfix").postfix
local matches = require("luasnip.extras.postfix").matches

return {
  -- Postfix: expr.var → varname=expr (simple assignment)
  postfix({ trig = ".var", match_pattern = matches.line }, {
    d(1, function(_, parent)
      local line = parent.snippet.env.POSTFIX_MATCH
      local indent = line:match "^%s*" or ""
      local expr = line:gsub("^%s+", "")
      return sn(nil, {
        t(indent),
        i(1, "var"),
        t "=",
        t(expr),
      })
    end, {}),
  }),
  -- Postfix: command.com → varname=$(command) (command substitution)
  postfix({ trig = ".com", match_pattern = matches.line }, {
    d(1, function(_, parent)
      local line = parent.snippet.env.POSTFIX_MATCH
      local indent = line:match "^%s*" or ""
      local cmd = line:gsub("^%s+", "")
      return sn(nil, {
        t(indent),
        i(1, "result"),
        t "=$(",
        t(cmd),
        t ")",
      })
    end, {}),
  }),
  -- Postfix: var.len → ${#var} (string length)
  postfix({ trig = ".len", match_pattern = matches.line }, {
    d(1, function(_, parent)
      local line = parent.snippet.env.POSTFIX_MATCH
      local indent = line:match "^%s*" or ""
      local before = line:gsub("^%s*", ""):gsub("([%w_]+)$", "")
      local var = line:match "([%w_]+)$" or ""
      return sn(nil, { t(indent .. before .. "${#" .. var .. "}") })
    end, {}),
  }),
  -- Postfix: var.print → printf '<i1>%s<i2>\n' "$var"
  postfix({ trig = ".print", match_pattern = matches.line }, {
    d(1, function(_, parent)
      local line = parent.snippet.env.POSTFIX_MATCH
      local indent = line:match "^%s*" or ""
      local var = line:gsub("^%s+", "")
      return sn(nil, {
        t(indent .. "printf '"),
        i(1),
        t "%s",
        i(2),
        t("\\n' \"$" .. var .. '"'),
      })
    end, {}),
  }),
  -- Strict mode for bash script
  s("start", {
    t {
      "#!/usr/bin/env bash",
      "",
      "set -eo pipefail",
      "",
      "# Add source and line number when running in debug mode: __run_with_xtrace.sh $TM_FILENAME",
      "# Set new line and tab for word splitting",
      "IFS=$'\\n\\t'",
      "",
      "",
    },
  }),

  -- Read file line by line
  s("while_file", {
    t {
      "while IFS= read -r line; do",
      "",
      '    echo "$line"',
      "",
      "done </",
    },
    i(0),
  }),
}
