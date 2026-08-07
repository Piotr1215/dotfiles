#!/usr/bin/env bats
#
# Covers __snippet_picker.sh without a display: xdotool and xclip are stubbed,
# so the paste path is exercised end to end and the assertions read what would
# have reached the clipboard and which keys would have been sent. rofi is never
# invoked, since every test drives either --list or direct mode.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	PICKER="$REPO_ROOT/scripts/__snippet_picker.sh"
	SNIPPETS="$BATS_TEST_TMPDIR/snippets"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	SPY="$BATS_TEST_TMPDIR/spy"
	mkdir -p "$SNIPPETS" "$STUB_BIN" "$SPY"

	# xclip stub: -o prints the stored clipboard, otherwise stdin becomes it.
	# Every write is also appended to a log, so a test can tell the body write
	# apart from the restore that follows a second later.
	cat > "$STUB_BIN/xclip" <<-STUB
		#!/usr/bin/env bash
		for a in "\$@"; do [ "\$a" = "-o" ] && { cat "$SPY/clipboard" 2>/dev/null; exit 0; }; done
		tee "$SPY/clipboard" >> "$SPY/clipboard.log"
	STUB

	# xdotool stub: record the key invocations, send nothing.
	cat > "$STUB_BIN/xdotool" <<-STUB
		#!/usr/bin/env bash
		echo "\$*" >> "$SPY/xdotool.log"
	STUB

	chmod +x "$STUB_BIN/xclip" "$STUB_BIN/xdotool"
	export PATH="$STUB_BIN:$PATH"
	export AI_SNIPPETS_DIR="$SNIPPETS"
}

@test "reflow joins a hard-wrapped paragraph into one line" {
	printf 'Audit the topic itself: is it\nactually finished, or left\nhalf-done?\n' > "$SNIPPETS/wrapped.md"
	run "$PICKER" 0 wrapped
	[ "$status" -eq 0 ]
	[ "$(head -1 "$SPY/clipboard")" = "Audit the topic itself: is it actually finished, or left half-done?" ]
	[ "$(wc -l < "$SPY/clipboard")" -eq 1 ]
}

@test "reflow keeps blank lines and joins wrapped list items" {
	printf 'Then answer:\n\n- what is still pending, or\n  deliberately skipped\n- what is not wired up\n' > "$SNIPPETS/listy.md"
	run "$PICKER" 0 listy
	[ "$status" -eq 0 ]
	[ "$(sed -n 1p "$SPY/clipboard")" = "Then answer:" ]
	[ "$(sed -n 2p "$SPY/clipboard")" = "" ]
	[ "$(sed -n 3p "$SPY/clipboard")" = "- what is still pending, or deliberately skipped" ]
	[ "$(sed -n 4p "$SPY/clipboard")" = "- what is not wired up" ]
}

@test "paste always ends with exactly one trailing newline" {
	# The cursor must land on a fresh line below the text whatever the file
	# was saved with, so both extremes have to normalise to the same thing.
	printf 'no trailing newline' > "$SNIPPETS/bare.md"
	printf 'three trailing newlines\n\n\n' > "$SNIPPETS/extra.md"

	# wc -l counts newlines, so 1 is the assertion: the missing one was added
	# in the first case and the surplus two were dropped in the second.
	run "$PICKER" 0 bare
	[ "$status" -eq 0 ]
	[ "$(wc -l < "$SPY/clipboard")" -eq 1 ]

	: > "$SPY/clipboard.log"
	run "$PICKER" 0 extra
	[ "$status" -eq 0 ]
	[ "$(wc -l < "$SPY/clipboard")" -eq 1 ]
}

@test "direct mode resolves a name with or without its extension" {
	printf 'body text\n' > "$SNIPPETS/open-the-link.md"
	run "$PICKER" 0 open-the-link
	[ "$status" -eq 0 ]
	run "$PICKER" 0 open-the-link.md
	[ "$status" -eq 0 ]
}

@test "direct mode fails loudly on an unknown snippet" {
	printf 'body\n' > "$SNIPPETS/real.md"
	run "$PICKER" 0 ghost
	[ "$status" -ne 0 ]
	[[ "$output" == *"No snippet named 'ghost'"* ]]
}

@test "the trigger is erased with one backspace per character, before the paste" {
	printf 'body\n' > "$SNIPPETS/x.md"
	run "$PICKER" 4 x
	[ "$status" -eq 0 ]
	# ";;br" is 4 chars, so 4 BackSpace, and the paste key comes after them.
	[ "$(grep -c BackSpace "$SPY/xdotool.log")" -eq 1 ]
	[ "$(head -1 "$SPY/xdotool.log" | grep -o BackSpace | wc -l)" -eq 4 ]
	[ "$(sed -n 2p "$SPY/xdotool.log")" = "key --clearmodifiers shift+Insert" ]
}

@test "an erase count of 0 sends no backspaces" {
	printf 'body\n' > "$SNIPPETS/y.md"
	run "$PICKER" 0 y
	[ "$status" -eq 0 ]
	[ "$(grep -c BackSpace "$SPY/xdotool.log")" -eq 0 ]
}

@test "the clipboard is restored after the paste" {
	printf 'previously copied' > "$SPY/clipboard"
	printf 'snippet body\n' > "$SNIPPETS/z.md"
	run "$PICKER" 0 z
	[ "$status" -eq 0 ]
	# The restore runs in a backgrounded subshell after a delay.
	sleep 1.5
	[ "$(cat "$SPY/clipboard")" = "previously copied" ]
}

@test "--list shows every snippet with an excerpt of the reflowed body" {
	printf 'first line here\nsecond line\n' > "$SNIPPETS/alpha.md"
	printf 'other body\n' > "$SNIPPETS/beta_two.md"
	run "$PICKER" --list
	[ "$status" -eq 0 ]
	[[ "$output" == *"alpha"* ]]
	[[ "$output" == *"beta two"* ]]
	[[ "$output" == *"first line here second line"* ]]
}

@test "an empty snippet directory is an error, not an empty menu" {
	run "$PICKER" --list
	[ "$status" -ne 0 ]
	[[ "$output" == *"No snippets"* ]]
}
