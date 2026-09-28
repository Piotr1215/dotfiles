package.path = (os.getenv("DOTFILES") or vim.fn.expand("~/dev/dotfiles")) .. "/.config/nvim/lua/" .. "?.lua;" .. package.path
local m = require("custom-completions.models")
local fails = 0
local function eq(name, want, got)
  if vim.inspect(want) == vim.inspect(got) then print("PASS  " .. name)
  else fails = fails + 1; print("FAIL  " .. name .. ": want " .. vim.inspect(want) .. " got " .. vim.inspect(got)) end
end
eq("role from claude line", "claude", m.role_for_line("AGENT_MODEL_CLAUDE=cl"))
eq("role keeps the escalate suffix", "claude-escalate", m.role_for_line("AGENT_MODEL_CLAUDE_ESCALATE="))
eq("comment line offers nothing", nil, m.role_for_line("# AGENT_MODEL_CLAUDE=x"))
eq("value position only", nil, m.role_for_line("AGENT_MODEL_CLAUDE"))
local items = m.items_for_line("AGENT_MODEL_CODEX=")
local labels = {}
for _, i in ipairs(items) do table.insert(labels, i.label) end
eq("codex offers tier aliases", { "sol", "astra", "terra", "luna" }, labels)
eq("current value sorts first", "0", items[1].sortText)
eq("current value is marked", "current", items[1].detail)
eq("unknown role offers nothing", {}, m.items_for_line("AGENT_MODEL_NOPE="))
vim.cmd(fails == 0 and "qa!" or "cq!")
