-- Tests for the im/am code block text objects.
-- Run: nvim --headless --clean -u NONE -l tests/nvim/codeblock_textobj_test.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*)/")
dofile(here .. "/../../.config/nvim/lua/user_functions/codeblock_textobj.lua")

local buffer = {
	"intro text", -- 1
	"```lua", -- 2
	"first", -- 3
	"```", -- 4
	"middle text", -- 5
	"```sh", -- 6
	"second", -- 7
	"```", -- 8
	"trailing text", -- 9
}

local failures = 0

-- Yank with the given keys from the given line and compare the unnamed register
local function check(name, cursor_line, keys, want)
	vim.cmd("enew!")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, buffer)
	vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
	vim.fn.setreg('"', "")

	vim.cmd("normal " .. keys)

	local got = vim.fn.getreg('"')
	if got ~= want then
		failures = failures + 1
		print(string.format("FAIL %s\n  want %q\n  got  %q", name, want, got))
	else
		print("PASS " .. name)
	end
end

check("cursor above every block selects the next one", 1, "yim", "first\n")
check("cursor inside the first block", 3, "yim", "first\n")
check("cursor on an opening fence", 2, "yim", "first\n")
check("cursor on a closing fence", 4, "yim", "first\n")
check("cursor between blocks selects the next one", 5, "yim", "second\n")
check("cursor inside the second block", 7, "yim", "second\n")
check("cursor below every block falls back to the previous one", 9, "yim", "second\n")
check("am above every block selects the next one", 1, "yam", "```lua\nfirst\n```\n")
check("am below every block falls back to the previous one", 9, "yam", "```sh\nsecond\n```\n")

-- A buffer without fences must leave the text alone
vim.cmd("enew!")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "no fences here", "at all" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
pcall(vim.cmd, "normal yim")
if vim.fn.getline(1) ~= "no fences here" or vim.fn.line("$") ~= 2 then
	failures = failures + 1
	print("FAIL buffer without a code block must stay untouched")
else
	print("PASS buffer without a code block stays untouched")
end

if failures > 0 then
	print(failures .. " failure(s)")
	vim.cmd("cquit! 1")
end

print("all tests passed")
vim.cmd("qa!")
