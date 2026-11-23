#!/usr/bin/env bats
#
# Covers __value_picker.sh without a display: rofi and xdotool are stubbed and
# log their calls, so a test reads whether a menu opened and what was typed.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	PICKER="$REPO_ROOT/scripts/__value_picker.sh"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	SPY="$BATS_TEST_TMPDIR/spy"
	export VALUE_SETS_DIR="$BATS_TEST_TMPDIR/sets"
	mkdir -p "$STUB_BIN" "$SPY" "$VALUE_SETS_DIR"
	for tool in rofi xdotool notify-send; do
		printf '#!/usr/bin/env bash\necho "$*" >> "%s/%s.log"\n' "$SPY" "$tool" > "$STUB_BIN/$tool"
	done
	chmod +x "$STUB_BIN"/*
	export PATH="$STUB_BIN:$PATH"
}

@test "a set with nothing to offer opens no menu and leaves the trigger" {
	printf '#!/usr/bin/env bash\ntrue\n' > "$VALUE_SETS_DIR/empty"
	chmod +x "$VALUE_SETS_DIR/empty"
	run "$PICKER" empty 10
	[ "$status" -eq 0 ]
	[ ! -e "$SPY/rofi.log" ]
	[ ! -e "$SPY/xdotool.log" ]
}

@test "a set with one value types it without a menu, after erasing the trigger" {
	printf '#!/usr/bin/env bash\necho "/a/b.jsonl | label"\n' > "$VALUE_SETS_DIR/one"
	chmod +x "$VALUE_SETS_DIR/one"
	run "$PICKER" one 2
	[ "$status" -eq 0 ]
	[ ! -e "$SPY/rofi.log" ]
	[ "$(sed -n 1p "$SPY/xdotool.log")" = "key --clearmodifiers BackSpace BackSpace" ]
	[ "$(sed -n 2p "$SPY/xdotool.log")" = "type --clearmodifiers --delay 12 -- /a/b.jsonl" ]
}

# rofi stub that records its menu on stdin and answers with $1 (rofi's "-format
# 'i s'" reply), so a test sees both what was shown and what got typed.
rofi_answers() {
	printf '#!/usr/bin/env bash\necho "$*" >> "%s/rofi.log"\ncat > "%s/rofi.menu"\nprintf "%%s\\n" "%s"\n' \
		"$SPY" "$SPY" "$1" > "$STUB_BIN/rofi"
	chmod +x "$STUB_BIN/rofi"
}

@test "a tab line shows only its label and types the hidden value" {
	printf '@"u1|D-1|r|fix a"\tfix a  D-1\n@"u2|D-2|r|fix b"\tfix b  D-2\n' > "$VALUE_SETS_DIR/tabs"
	rofi_answers "1 fix b  D-2"
	run "$PICKER" tabs 0
	[ "$status" -eq 0 ]
	[ "$(cat "$SPY/rofi.menu")" = "$(printf 'fix a  D-1\nfix b  D-2')" ]
	[[ "$(cat "$SPY/rofi.log")" == *"-format i s"* ]]
	[ "$(tail -1 "$SPY/xdotool.log")" = 'type --clearmodifiers --delay 12 -- @"u2|D-2|r|fix b"' ]
}

@test "a pipe line still shows whole and types the part before the pipe" {
	printf 'v1 | one\nv2 | two\n' > "$VALUE_SETS_DIR/pipes"
	rofi_answers "0 v1 | one"
	run "$PICKER" pipes 0
	[ "$status" -eq 0 ]
	[ "$(cat "$SPY/rofi.menu")" = "$(printf 'v1 | one\nv2 | two')" ]
	[ "$(tail -1 "$SPY/xdotool.log")" = "type --clearmodifiers --delay 12 -- v1" ]
}

@test "a custom entry with no matching row types what was entered" {
	printf 'v1\nv2\n' > "$VALUE_SETS_DIR/plain"
	rofi_answers "-1 typed by hand"
	run "$PICKER" plain 0
	[ "$status" -eq 0 ]
	[ "$(tail -1 "$SPY/xdotool.log")" = "type --clearmodifiers --delay 12 -- typed by hand" ]
}

@test "a single tab line types its hidden value without a menu" {
	printf '@"u1|D-1|r|fix a"\tfix a\n' > "$VALUE_SETS_DIR/onetab"
	run "$PICKER" onetab 0
	[ "$status" -eq 0 ]
	[ ! -e "$SPY/rofi.log" ]
	[ "$(tail -1 "$SPY/xdotool.log")" = 'type --clearmodifiers --delay 12 -- @"u1|D-1|r|fix a"' ]
}

@test "a live set's values that start with # reach the menu" {
	printf '#!/usr/bin/env bash\nprintf "#alpha\\n\\n#beta\\n"\n' > "$VALUE_SETS_DIR/hashes"
	chmod +x "$VALUE_SETS_DIR/hashes"
	rofi_answers "1 #beta"
	run "$PICKER" hashes 0
	[ "$status" -eq 0 ]
	[ "$(cat "$SPY/rofi.menu")" = "$(printf '#alpha\n#beta')" ]
	[ "$(tail -1 "$SPY/xdotool.log")" = "type --clearmodifiers --delay 12 -- #beta" ]
}

@test "a plain set still drops # comments and blank lines" {
	printf '# header\nv1\n\n  # indented note\nv2\n' > "$VALUE_SETS_DIR/commented"
	rofi_answers "0 v1"
	run "$PICKER" commented 0
	[ "$status" -eq 0 ]
	[ "$(cat "$SPY/rofi.menu")" = "$(printf 'v1\nv2')" ]
}
