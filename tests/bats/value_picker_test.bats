#!/usr/bin/env bats
#
# Covers __value_picker.sh without a display: rofi, xdotool and xclip are
# stubbed and log their calls, so a test reads whether a menu opened, what was
# pasted, and what the clipboard held before and after.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	PICKER="$REPO_ROOT/scripts/__value_picker.sh"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	SPY="$BATS_TEST_TMPDIR/spy"
	export VALUE_SETS_DIR="$BATS_TEST_TMPDIR/sets"
	export VALUE_PICKER_RESTORE_DELAY=0
	mkdir -p "$STUB_BIN" "$SPY" "$VALUE_SETS_DIR"
	for tool in rofi xdotool notify-send; do
		printf '#!/usr/bin/env bash\necho "$*" >> "%s/%s.log"\n' "$SPY" "$tool" > "$STUB_BIN/$tool"
	done

	# xclip stub. "-t TARGETS -o" prints $SPY/targets (fails when absent, as a
	# clipboard with no owner does), "-o" prints the stored content, and a write
	# stores stdin and logs "<target or -><TAB><content>" to clipboard.log.
	cat > "$STUB_BIN/xclip" <<-STUB
		#!/usr/bin/env bash
		target=-; out=0
		while [ \$# -gt 0 ]; do
			case "\$1" in -t) target="\$2"; shift ;; -o) out=1 ;; esac
			shift
		done
		if [ \$out = 1 ]; then
			if [ "\$target" = TARGETS ]; then cat "$SPY/targets" 2>/dev/null || exit 1; exit 0; fi
			cat "$SPY/clipboard" 2>/dev/null || exit 1
			exit 0
		fi
		cat > "$SPY/clipboard"
		printf '%s\t%s\n' "\$target" "\$(cat "$SPY/clipboard")" >> "$SPY/clipboard.log"
	STUB
	chmod +x "$STUB_BIN"/*
	export PATH="$STUB_BIN:$PATH"

	# Default: text on the clipboard, as after an ordinary copy.
	printf 'TARGETS\nUTF8_STRING\nSTRING\n' > "$SPY/targets"
	printf 'old text' > "$SPY/clipboard"
}

# rofi stub that records its menu on stdin and answers with $1 (rofi's "-format
# 'i s'" reply), so a test sees both what was shown and what got picked.
rofi_answers() {
	printf '#!/usr/bin/env bash\necho "$*" >> "%s/rofi.log"\ncat > "%s/rofi.menu"\nprintf "%%s\\n" "%s"\n' \
		"$SPY" "$SPY" "$1" > "$STUB_BIN/rofi"
	chmod +x "$STUB_BIN/rofi"
}

# The value the pick put on the clipboard: the first write.
pasted() { sed -n 1p "$SPY/clipboard.log" | cut -f2-; }

# Wait for the background restore, the clipboard write after the paste.
wait_restore() {
	for _ in $(seq 40); do
		[ "$(wc -l < "$SPY/clipboard.log" 2>/dev/null || echo 0)" -ge 2 ] && return 0
		sleep 0.05
	done
	return 1
}

@test "a set with nothing to offer opens no menu and leaves the trigger" {
	printf '#!/usr/bin/env bash\ntrue\n' > "$VALUE_SETS_DIR/empty"
	chmod +x "$VALUE_SETS_DIR/empty"
	run "$PICKER" empty 10
	[ "$status" -eq 0 ]
	[ ! -e "$SPY/rofi.log" ]
	[ ! -e "$SPY/xdotool.log" ]
	[ ! -e "$SPY/clipboard.log" ]
}

@test "a set with one value pastes it without a menu, after erasing the trigger" {
	printf '#!/usr/bin/env bash\necho "/a/b.jsonl | label"\n' > "$VALUE_SETS_DIR/one"
	chmod +x "$VALUE_SETS_DIR/one"
	run "$PICKER" one 2
	[ "$status" -eq 0 ]
	[ ! -e "$SPY/rofi.log" ]
	[ "$(sed -n 1p "$SPY/xdotool.log")" = "key --clearmodifiers BackSpace BackSpace" ]
	[ "$(sed -n 2p "$SPY/xdotool.log")" = "key --clearmodifiers shift+Insert" ]
	[ "$(pasted)" = "/a/b.jsonl" ]
}

@test "a pick is pasted, never typed, and the copied text comes back" {
	printf 'v1\nv2\n' > "$VALUE_SETS_DIR/plain"
	rofi_answers "1 v2"
	run "$PICKER" plain 0
	[ "$status" -eq 0 ]
	[ "$(pasted)" = "v2" ]
	! grep -q '^type' "$SPY/xdotool.log"
	wait_restore
	[ "$(sed -n 2p "$SPY/clipboard.log")" = "$(printf -- '-\told text')" ]
}

@test "an image on the clipboard comes back as an image" {
	printf 'TARGETS\nimage/png\n' > "$SPY/targets"
	printf 'PNGBYTES' > "$SPY/clipboard"
	printf 'v1\nv2\n' > "$VALUE_SETS_DIR/plain"
	rofi_answers "0 v1"
	run "$PICKER" plain 0
	[ "$status" -eq 0 ]
	[ "$(pasted)" = "v1" ]
	wait_restore
	[ "$(sed -n 2p "$SPY/clipboard.log")" = "$(printf 'image/png\tPNGBYTES')" ]
}

@test "an empty clipboard keeps the pasted value, nothing to restore" {
	rm -f "$SPY/targets" "$SPY/clipboard"
	printf 'v1\nv2\n' > "$VALUE_SETS_DIR/plain"
	rofi_answers "0 v1"
	run "$PICKER" plain 0
	[ "$status" -eq 0 ]
	[ "$(pasted)" = "v1" ]
	! wait_restore
}

@test "copied files are left on the clipboard and the value is typed instead" {
	printf 'TARGETS\nx-special/gnome-copied-files\ntext/uri-list\nUTF8_STRING\n' > "$SPY/targets"
	printf 'v1\nv2\n' > "$VALUE_SETS_DIR/plain"
	rofi_answers "0 v1"
	run "$PICKER" plain 0
	[ "$status" -eq 0 ]
	[ ! -e "$SPY/clipboard.log" ]
	[ "$(tail -1 "$SPY/xdotool.log")" = "type --clearmodifiers --delay 12 -- v1" ]
}

@test "a tab line shows only its label and pastes the hidden value" {
	printf '@"u1|D-1|r|fix a"\tfix a  D-1\n@"u2|D-2|r|fix b"\tfix b  D-2\n' > "$VALUE_SETS_DIR/tabs"
	rofi_answers "1 fix b  D-2"
	run "$PICKER" tabs 0
	[ "$status" -eq 0 ]
	[ "$(cat "$SPY/rofi.menu")" = "$(printf 'fix a  D-1\nfix b  D-2')" ]
	[[ "$(cat "$SPY/rofi.log")" == *"-format i s"* ]]
	[ "$(pasted)" = '@"u2|D-2|r|fix b"' ]
}

@test "a pipe line still shows whole and pastes the part before the pipe" {
	printf 'v1 | one\nv2 | two\n' > "$VALUE_SETS_DIR/pipes"
	rofi_answers "0 v1 | one"
	run "$PICKER" pipes 0
	[ "$status" -eq 0 ]
	[ "$(cat "$SPY/rofi.menu")" = "$(printf 'v1 | one\nv2 | two')" ]
	[ "$(pasted)" = "v1" ]
}

@test "a custom entry with no matching row pastes what was entered" {
	printf 'v1\nv2\n' > "$VALUE_SETS_DIR/plain"
	rofi_answers "-1 typed by hand"
	run "$PICKER" plain 0
	[ "$status" -eq 0 ]
	[ "$(pasted)" = "typed by hand" ]
}

@test "a single tab line pastes its hidden value without a menu" {
	printf '@"u1|D-1|r|fix a"\tfix a\n' > "$VALUE_SETS_DIR/onetab"
	run "$PICKER" onetab 0
	[ "$status" -eq 0 ]
	[ ! -e "$SPY/rofi.log" ]
	[ "$(pasted)" = '@"u1|D-1|r|fix a"' ]
}

@test "a live set's values that start with # reach the menu" {
	printf '#!/usr/bin/env bash\nprintf "#alpha\\n\\n#beta\\n"\n' > "$VALUE_SETS_DIR/hashes"
	chmod +x "$VALUE_SETS_DIR/hashes"
	rofi_answers "1 #beta"
	run "$PICKER" hashes 0
	[ "$status" -eq 0 ]
	[ "$(cat "$SPY/rofi.menu")" = "$(printf '#alpha\n#beta')" ]
	[ "$(pasted)" = "#beta" ]
}

@test "a plain set still drops # comments and blank lines" {
	printf '# header\nv1\n\n  # indented note\nv2\n' > "$VALUE_SETS_DIR/commented"
	rofi_answers "0 v1"
	run "$PICKER" commented 0
	[ "$status" -eq 0 ]
	[ "$(cat "$SPY/rofi.menu")" = "$(printf 'v1\nv2')" ]
}

@test "after rofi closes, keys wait until the original window has focus again" {
	# getactivewindow answers from a queue: the window the trigger was typed in,
	# then rofi's own focus twice, then the original window back.
	printf '111\n222\n222\n111\n' > "$SPY/active"
	cat > "$STUB_BIN/xdotool" <<-STUB
		#!/usr/bin/env bash
		echo "\$*" >> "$SPY/xdotool.log"
		if [ "\$1" = getactivewindow ]; then
			head -1 "$SPY/active"; sed -i 1d "$SPY/active"
		fi
	STUB
	printf 'v1\nv2\n' > "$VALUE_SETS_DIR/plain"
	rofi_answers "0 v1"
	run "$PICKER" plain 3
	[ "$status" -eq 0 ]
	[ "$(grep -c '^getactivewindow' "$SPY/xdotool.log")" -eq 4 ]
	# The erase comes only after the fourth focus check saw the original window.
	last_check=$(grep -n '^getactivewindow' "$SPY/xdotool.log" | tail -1 | cut -d: -f1)
	erase=$(grep -n BackSpace "$SPY/xdotool.log" | cut -d: -f1)
	[ "$erase" -gt "$last_check" ]
}
