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
