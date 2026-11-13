-- Tests for markdown reading mode: the spaced copy (blank lines between list
-- items, none inside fenced code, a line map back to the source) and the link
-- collector behind the picker.
-- Run: nvim --headless --clean -u NONE -l tests/nvim/markdown_reader_test.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*)/")
local root = here .. "/../../.config/nvim/lua/markdown_reader/"
local reader = dofile(root .. "copy.lua")
local links = dofile(root .. "links.lua")

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

local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/sub", "p")
vim.fn.writefile({}, dir .. "/journey.sh")
vim.fn.writefile({}, dir .. "/sub/notes.md")
local found = links.links({
	"See [notes](sub/notes.md#top) and `journey.sh`.",
	"Docs at https://neovim.io/doc, twice: https://neovim.io/doc.",
	"Missing `nope.sh`, a version 1.2 number, and `$0` or `$12` shell variables.",
	"```sh",
	"cat journey.sh https://example.com/in-code",
	"```",
}, dir)
check(
	"links: existing files and urls once each, in order, code skipped",
	vim.tbl_map(function(e)
		return e.kind .. " " .. e.target:gsub("^" .. vim.pesc(dir), "") .. " " .. e.lnum
	end, found),
	{ "file /sub/notes.md 1", "file /journey.sh 1", "url https://neovim.io/doc 2" }
)
vim.fn.delete(dir, "rf")

if failures > 0 then
	print(failures .. " failure(s)")
	vim.cmd("cquit! 1")
end

print("all tests passed")
vim.cmd("qa!")
