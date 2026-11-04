package.path = (os.getenv("DOTFILES") or vim.fn.expand("~/dev/dotfiles")) .. "/.config/nvim/lua/?.lua;" .. package.path
local source
package.preload.cmp = function()
	return {
		register_source = function(_, value)
			source = value
		end,
	}
end
local m = require("custom-completions.pass")
local fails = 0
local function eq(name, want, got)
	if vim.deep_equal(want, got) then
		print("PASS  " .. name)
	else
		fails = fails + 1
		print("FAIL  " .. name .. ": want " .. vim.inspect(want) .. " got " .. vim.inspect(got))
	end
end

local store = vim.fn.tempname()
for _, path in ipairs({
	"personal/MULLAVAD_PRIVATE_KEY.gpg",
	"work/TF_VAR_pam_github_read_token.gpg",
	"work/kctx/vcluster/loft.rocks.gpg",
	"me@example.com.gpg",
	".git/objects/stale.gpg",
	"work/notes.txt",
}) do
	vim.fn.mkdir(vim.fs.dirname(store .. "/" .. path), "p")
	vim.fn.writefile({}, store .. "/" .. path)
end
vim.env.PASSWORD_STORE_DIR = store

eq("entries come from .gpg names, hidden dirs skipped", {
	"me@example.com",
	"personal/MULLAVAD_PRIVATE_KEY",
	"work/TF_VAR_pam_github_read_token",
	"work/kctx/vcluster/loft.rocks",
}, m.entries())
eq("export line uses the basename", "_pass_export MULLAVAD_PRIVATE_KEY personal/MULLAVAD_PRIVATE_KEY", m.export_line("personal/MULLAVAD_PRIVATE_KEY"))
eq("var name keeps case", "TF_VAR_pam_github_read_token", m.var_name("work/TF_VAR_pam_github_read_token"))
eq("var name replaces invalid characters", "loft_rocks", m.var_name("work/kctx/vcluster/loft.rocks"))
eq("var name never starts with a digit", "_1KEY", m.var_name("personal/1KEY"))

local items
source:complete({ context = { cursor_before_line = "pass" } }, function(result)
	items = result
end)
eq("pass offers every entry", 4, #items)
eq("item inserts the export line", "_pass_export MULLAVAD_PRIVATE_KEY personal/MULLAVAD_PRIVATE_KEY", items[2].insertText)
eq("item filters on the pass prefix", "passpersonal/MULLAVAD_PRIVATE_KEY", items[2].filterText)
eq("indented pass with a filter still completes", 4, #m.items_for_line("  passpers"))
eq("pass mid-line offers nothing", {}, m.items_for_line("export X=pass"))
eq("existing export line offers nothing", {}, m.items_for_line("_pass_export X pers"))
eq("keyword pattern spans the filter", 0, vim.regex([[\%(]] .. source:get_keyword_pattern() .. [[\)\m$]]):match_str("passwork/kctx/loft.r"))

vim.cmd("edit " .. vim.fn.fnameescape(store .. "/.envrc"))
eq("available in .envrc", true, source:is_available())
vim.cmd("edit " .. vim.fn.fnameescape(store .. "/run.sh"))
eq("not available elsewhere", false, source:is_available())

vim.env.PASSWORD_STORE_DIR = store .. "/missing"
eq("missing store offers nothing", {}, m.entries())
vim.fn.delete(store, "rf")
vim.cmd(fails == 0 and "qa!" or "cq!")
