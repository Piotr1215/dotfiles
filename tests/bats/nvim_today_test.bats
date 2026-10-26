#!/usr/bin/env bats
# :Today (user_functions/obsidian_notes.lua) opens the path __daily_note.sh
# prints and reports the script's failure instead of opening anything.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	export DAILY_NOTE_CMD="$BATS_TEST_TMPDIR/daily"
	NOTE="$BATS_TEST_TMPDIR/vault/_Current/2026-10-26.md"
	mkdir -p "${NOTE%/*}"
	printf '# 2026-10-26\n' >"$NOTE"
}

# today_buffer: run :Today in a bare nvim and print the buffer it ends in.
today_buffer() {
	timeout 30 nvim --headless -u NONE \
		-c "luafile $REPO_ROOT/.config/nvim/lua/user_functions/obsidian_notes.lua" \
		-c 'Today' \
		-c 'lua io.stdout:write(vim.api.nvim_buf_get_name(0))' \
		-c 'qa!' 2>/dev/null
}

@test ":Today opens the note the script prints" {
	printf '#!/usr/bin/env bash\necho %q\n' "$NOTE" >"$DAILY_NOTE_CMD"
	chmod +x "$DAILY_NOTE_CMD"
	[ "$(today_buffer)" = "$NOTE" ]
}

@test ":Today opens nothing when the script fails" {
	printf '#!/usr/bin/env bash\necho %q\necho boom >&2\nexit 1\n' "$NOTE" >"$DAILY_NOTE_CMD"
	chmod +x "$DAILY_NOTE_CMD"
	[ "$(today_buffer)" = "" ]
}
