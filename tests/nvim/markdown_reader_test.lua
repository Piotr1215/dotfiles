-- Tests for markdown reading mode: the gaps between list items and the
-- paragraph motions and text objects that count them, and the link collector
-- behind the picker.
-- Run: nvim --headless --clean -u NONE -l tests/nvim/markdown_reader_test.lua

local here = debug.getinfo(1, "S").source:sub(2):match("(.*)/")
local root = here .. "/../../.config/nvim/lua/markdown_reader/"
local paragraphs = dofile(root .. "paragraphs.lua")
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

local doc = {
	"# Title", -- 1
	"", -- 2
	"Intro line one", -- 3
	"intro line two", -- 4
	"", -- 5
	"- one", -- 6
	"- two", -- 7
	"  more of two", -- 8
	"- three", -- 9
	"", -- 10
	"```sh", -- 11
	"- not a list", -- 12
	"- still code", -- 13
	"```", -- 14
	"", -- 15
	"", -- 16
	"end", -- 17
}
local gaps = paragraphs.gaps(doc)

check("gaps: between list items only, none in code or under a continuation line", vim.tbl_keys(gaps), { 6 })
check("gaps: text without lists has none", next(paragraphs.gaps({ "a", "", "b" })), nil)

local function walk(row, forward, n)
	local out = {}
	for _ = 1, n do
		row = paragraphs.stop(doc, gaps, row, forward)
		out[#out + 1] = row
	end
	return out
end
check("} stops on empty lines after text and on the item below a gap", walk(1, true, 6), { 2, 5, 7, 10, 15, 17 })
check("{ stops on empty lines before text and on the item below a gap", walk(17, false, 6), { 16, 10, 7, 5, 2, 1 })

local function span(row, around)
	return { paragraphs.paragraph(doc, gaps, row, around) }
end
check("ip: a paragraph without gaps", span(4, false), { 3, 4 })
check("ip: one list item, cut at its gap", span(6, false), { 6, 6 })
check("ip: an item with its continuation line", span(8, false), { 7, 9 })
check("ip: on an empty line, the run of empty lines", span(16, false), { 15, 16 })
check("ap: the item plus the empty line after the list", span(9, true), { 7, 10 })
check("ap: a gap adds nothing", span(6, true), { 6, 6 })
check("ap: last paragraph takes the empty lines before it", span(17, true), { 15, 17 })

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
