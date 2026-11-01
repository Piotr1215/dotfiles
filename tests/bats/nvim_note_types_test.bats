#!/usr/bin/env bats
# The Obsidian note picker (user_functions/obsidian_notes.lua) offers each note
# type and creates it in the right folder from the right template.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

# in_nvim: run a lua chunk with the module bound to m in a bare nvim.
# $1: lua chunk
in_nvim() {
	timeout 30 nvim --headless -u NONE \
		-c "lua package.path = '$REPO_ROOT/.config/nvim/lua/?.lua;' .. package.path" \
		-c "lua local m = require('user_functions.obsidian_notes'); $1" \
		-c 'qa!' 2>/dev/null
}

# note_commands: print the Obsidian commands that creating a note of a type runs.
# $1: note type
note_commands() {
	in_nvim "local seen = {}; vim.api.nvim_command = function(c) seen[#seen + 1] = c end; m.create_note_with_template('$1', 'trip'); io.stdout:write(table.concat(seen, '\n'))"
}

@test "the picker offers travel" {
	run in_nvim "vim.ui.select = function(items) io.stdout:write(table.concat(items, ' ')) end; m.select_note_type_and_create()"
	[[ " $output " == *" travel "* ]]
}

@test "a travel note lands in projects with the travel template" {
	run note_commands travel
	[[ "$output" == *":Obsidian new Notes/projects/trip"* ]]
	[[ "$output" == *":Obsidian template travel.md"* ]]
}

@test "other note types keep their own folder and template" {
	run note_commands areas
	[[ "$output" == *":Obsidian new Notes/areas/trip"* ]]
	[[ "$output" == *":Obsidian template areas.md"* ]]
}
