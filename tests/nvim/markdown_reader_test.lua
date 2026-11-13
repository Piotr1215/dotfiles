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

-- Refresh keeps the reader on the same text when lines move above it.
local before = {}
for i = 1, 60 do
	before[#before + 1] = "Paragraph " .. i
	before[#before + 1] = ""
end
local after = vim.list_extend({ "New line one", "New line two" }, before)
check("relocate: insertion above keeps the same paragraph", after[reader.relocate(before, 79, after)], "Paragraph 40")
check("relocate: a blank line keeps its offset below the paragraph", reader.relocate(before, 80, after), 82)
check("relocate: deletion above moves up with the text", reader.relocate(after, 81, before), 79)
check("relocate: text that vanished keeps the old row", reader.relocate({ "a", "gone", "c" }, 2, { "a", "c" }), 2)

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
local function show(e)
	return e.kind
		.. " "
		.. e.target:gsub("^" .. vim.pesc(dir), "")
		.. (e.kind == "file" and e.anchor and "#" .. e.anchor or "")
		.. " "
		.. e.lnum
end
check(
	"links: files keep their anchor, urls once each, in order, code skipped",
	vim.tbl_map(show, found),
	{ "file /sub/notes.md#top 1", "file /journey.sh 1", "url https://neovim.io/doc 2" }
)
check(
	"links: a same-page anchor is followable, a bare #word is not",
	vim.tbl_map(show, links.links({ "Jump to [setup](#Setup-Steps) or see #hashtag." }, dir)),
	{ "heading #Setup-Steps 1" }
)

local line = "See [notes](sub/notes.md#top) and https://neovim.io/doc here."
check("target_at: inside a markdown link label", links.target_at(line, 6, dir).anchor, "top")
check("target_at: on a bare url", links.target_at(line, 40, dir).target, "https://neovim.io/doc")
check("target_at: on plain text", links.target_at(line, 2, dir), nil)

check(
	"headings: levels and anchors, none from code",
	vim.tbl_map(function(h)
		return h.level .. " " .. h.slug .. " " .. h.lnum
	end, links.headings({ "# Setup Steps!", "text", "```sh", "# comment", "```", "### Done: yes" })),
	{ "1 setup-steps 1", "3 done-yes 6" }
)
check("slug matches a link written in another case", links.slug("Setup-Steps"), links.slug("Setup Steps"))
vim.fn.delete(dir, "rf")

if failures > 0 then
	print(failures .. " failure(s)")
	vim.cmd("cquit! 1")
end

print("all tests passed")
vim.cmd("qa!")
