-- Tests for the markdown reading copy: blank lines between list items, none
-- inside fenced code, and a line map back to the source.
-- Run: nvim --headless --clean -u NONE -l tests/nvim/markdown_reader_test.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*)/")
local reader = dofile(here .. "/../../.config/nvim/lua/user_functions/markdown_reader.lua")

local failures = 0

local function check(name, got, want)
	if vim.deep_equal(got, want) then
		print("PASS " .. name)
	else
		failures = failures + 1
		print(string.format("FAIL %s\n  want %s\n  got  %s", name, vim.inspect(want), vim.inspect(got)))
	end
end

local source = {
	"# Title", -- 1
	"- one", -- 2
	"- two", -- 3
	"1. first", -- 4
	"2. second", -- 5
	"```sh", -- 6
	"- not a list", -- 7
	"- still code", -- 8
	"```", -- 9
	"para", -- 10
}
local lines, map = reader.spaced_lines(source)

check("blank line between list items, none inside code", lines, {
	"# Title",
	"- one",
	"",
	"- two",
	"",
	"1. first",
	"",
	"2. second",
	"```sh",
	"- not a list",
	"- still code",
	"```",
	"para",
})
check("each source line maps to its line in the copy", map, { 1, 2, 4, 6, 8, 9, 10, 11, 12, 13 })

local plain = { "a", "", "b" }
check("text without lists is unchanged", (reader.spaced_lines(plain)), plain)

if failures > 0 then
	print(failures .. " failure(s)")
	vim.cmd("cquit! 1")
end

print("all tests passed")
vim.cmd("qa!")
