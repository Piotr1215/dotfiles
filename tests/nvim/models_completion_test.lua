package.path = (os.getenv("DOTFILES") or vim.fn.expand("~/dev/dotfiles")) .. "/.config/nvim/lua/?.lua;" .. package.path
local source
package.preload.cmp = function()
	return {
		register_source = function(_, value)
			source = value
		end,
	}
end
local m = require("custom-completions.models")
local fails = 0
local function eq(name, want, got)
	if vim.deep_equal(want, got) then
		print("PASS  " .. name)
	else
		fails = fails + 1
		print("FAIL  " .. name .. ": want " .. vim.inspect(want) .. " got " .. vim.inspect(got))
	end
end
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
vim.fn.writefile({ '["fixture-old-sol","fixture-new-sol","fixture-terra"]' }, tmp .. "/openai.json")
vim.env.MODEL_CATALOG_CACHE_DIR = tmp
vim.env.AGENT_MODEL_CODEX = "fixture-new-sol"

eq("role from claude line", "claude", m.role_for_line("AGENT_MODEL_CLAUDE=cl"))
eq("role keeps the escalate suffix", "claude-escalate", m.role_for_line("AGENT_MODEL_CLAUDE_ESCALATE="))
eq("comment line offers nothing", nil, m.role_for_line("# AGENT_MODEL_CLAUDE=x"))
eq("value position only", nil, m.role_for_line("AGENT_MODEL_CLAUDE"))
local expected = vim.fn.systemlist({ vim.fn.expand("~/.claude/scripts/__models.sh"), "candidates", "codex" })
eq("resolver succeeded", 0, vim.v.shell_error)
local items
source:complete({ context = { cursor_before_line = "AGENT_MODEL_CODEX=" } }, function(result)
	items = result
end)
eq("completion returns before resolver finishes", nil, items)
eq(
	"completion finishes",
	true,
	vim.wait(5000, function()
		return items ~= nil
	end)
)
local labels = {}
for _, item in ipairs(items or {}) do
	table.insert(labels, item.label)
end
eq("completion returns resolver ids", expected, labels)
eq("current value sorts first", "0", items and items[2].sortText)
eq("current value is marked", "current", items and items[2].detail)
local empty
m.items_for_line("# comment", function(result)
	empty = result
end)
eq("non-model line offers nothing", {}, empty)

local real_system, real_notify = vim.system, vim.notify
local notifications = {}
vim.notify = function(message)
	table.insert(notifications, message)
end
vim.system = function(_, _, callback)
	callback({ code = 1, stderr = "catalog unavailable" })
end
local failed
m.items_for_line("AGENT_MODEL_CODEX=", function(result)
	failed = result
end)
eq(
	"failure finishes",
	true,
	vim.wait(1000, function()
		return failed ~= nil
	end)
)
eq("failure returns no stale items", {}, failed)
eq("failure notifies", true, notifications[1] and notifications[1]:find("catalog unavailable", 1, true) ~= nil)
local calls = 0
vim.system = function(_, _, callback)
	calls = calls + 1
	callback(calls == 1 and { code = 0, stdout = "fixture-sol\n" } or { code = 1, stderr = "get failed" })
end
failed = nil
m.items_for_line("AGENT_MODEL_CODEX=", function(result)
	failed = result
end)
eq(
	"get failure finishes",
	true,
	vim.wait(1000, function()
		return failed ~= nil
	end)
)
eq("get failure returns no candidates", {}, failed)
eq("get failure notifies", true, notifications[2] and notifications[2]:find("get failed", 1, true) ~= nil)
vim.system, vim.notify = real_system, real_notify
vim.fn.delete(tmp, "rf")
vim.cmd(fails == 0 and "qa!" or "cq!")
