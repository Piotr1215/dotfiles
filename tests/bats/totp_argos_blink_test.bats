#!/usr/bin/env bats
#
# Covers the key glyph in .config/argos/totp.1s.sh, which is the only
# only signalling surface __secret_picker.sh has left: a red T while age waits
# for the key to be touched, a yellow flash once the value is on the clipboard,
# and no notification for either. Four silent failures to guard: a marker that
# outlives its window and leaves the panel flashing forever, a single button
# line (argos starts its line cycler only for two or more, so nothing would
# flash at all), a colour that lands on the line's first markup element and is
# dropped by the panel, and the two files drifting onto different marker paths,
# which would leave a copy looking like it did nothing.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	APPLET="$REPO_ROOT/.config/argos/totp.1s.sh"
	PICKER="$REPO_ROOT/scripts/__secret_picker.sh"

	export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
	mkdir -p "$XDG_RUNTIME_DIR"
	BLINK="$XDG_RUNTIME_DIR/secret-picker-blink"
	TOUCH="$XDG_RUNTIME_DIR/secret-picker-touch"
	CACHE="$XDG_RUNTIME_DIR/argos-totp-accounts"

	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$STUB_BIN"
	YKMAN_CALLS="$BATS_TEST_TMPDIR/ykman.calls"
	cat > "$STUB_BIN/ykman" <<EOF
#!/usr/bin/env bash
echo call >> "$YKMAN_CALLS"
printf 'GitHub:someone\nAWS:someone\n'
EOF
	chmod +x "$STUB_BIN/ykman"
	export PATH="$STUB_BIN:$PATH"
}

# Button lines are everything before the first --- separator. Argos cycles
# between them, which is what makes the badge flash.
button_lines() {
	sed -n '1,/^---$/p' <<< "$1" | sed '$d'
}

# $1 = how many seconds ago the copy happened.
blink_at_age() {
	touch -d "@$(($(date +%s) - $1))" "$BLINK"
}

@test "idle panel shows one line: the key and the account count" {
	run "$APPLET"
	[ "$status" -eq 0 ]
	local lines_out; lines_out="$(button_lines "$output")"
	[ "$(wc -l <<< "$lines_out")" -eq 1 ]
	[[ "$lines_out" == *"🔑"* ]]
	[[ "$lines_out" == *">2<"* ]]
}

@test "a copy flashes the badge yellow against black" {
	blink_at_age 0
	run "$APPLET"
	[ "$status" -eq 0 ]
	local lines_out; lines_out="$(button_lines "$output")"
	# Two lines or argos never starts the cycler and nothing flashes.
	[ "$(wc -l <<< "$lines_out")" -eq 2 ]
	# Yellow first: the cycler shows line one immediately, so the copy is
	# acknowledged on the tick rather than 800ms into it.
	[[ "$(sed -n 1p <<< "$lines_out")" == *"🟡"* ]]
	[[ "$(sed -n 2p <<< "$lines_out")" == *"⚫"* ]]
	# Argos prepends cycle lines to the menu unless they opt out, which would
	# push the account list down behind two junk rows.
	[ "$(grep -c 'dropdown=false' <<< "$lines_out")" -eq 2 ]
}

@test "the badge flashes for every second of the window" {
	local age
	for age in 0 1 2 3; do
		blink_at_age "$age"
		run "$APPLET"
		[ "$status" -eq 0 ]
		[ "$(wc -l <<< "$(button_lines "$output")")" -eq 2 ]
	done
}

@test "the blink ends and clears its own marker" {
	blink_at_age 4
	run "$APPLET"
	[ "$status" -eq 0 ]
	local lines_out; lines_out="$(button_lines "$output")"
	[ "$(wc -l <<< "$lines_out")" -eq 1 ]
	[[ "$lines_out" == *"🔑"* ]]
	# Left behind, the marker would be re-read as a copy that happened in the
	# past and the badge would flash on every future tick.
	[ ! -f "$BLINK" ]
}

@test "a marker dated in the future does not flash forever" {
	touch -d "@$(($(date +%s) + 3600))" "$BLINK"
	run "$APPLET"
	[ "$status" -eq 0 ]
	[ "$(wc -l <<< "$(button_lines "$output")")" -eq 1 ]
	[ ! -f "$BLINK" ]
}

@test "ykman is not touched again while the cache is warm" {
	run "$APPLET"
	[ "$(wc -l < "$YKMAN_CALLS")" -eq 1 ]
	run "$APPLET"
	run "$APPLET"
	# A one second applet that polled the USB key every tick would sit on it
	# while age or gpg wants a tap.
	[ "$(wc -l < "$YKMAN_CALLS")" -eq 1 ]
}

@test "a stale cache is refreshed and still serves the old count meanwhile" {
	run "$APPLET"
	touch -d "@$(($(date +%s) - 60))" "$CACHE"
	run "$APPLET"
	[ "$status" -eq 0 ]
	[[ "$(button_lines "$output")" == *">2<"* ]]
	# The refresh is detached, so give it a moment before counting the call.
	sleep 1
	[ "$(wc -l < "$YKMAN_CALLS")" -eq 2 ]
}

@test "a pending tap flashes a red T where the key sits" {
	touch "$TOUCH"
	run "$APPLET"
	[ "$status" -eq 0 ]
	local lines_out; lines_out="$(button_lines "$output")"
	[ "$(wc -l <<< "$lines_out")" -eq 2 ]
	[[ "$(sed -n 1p <<< "$lines_out")" == *"#ff3b30"* ]]
	[[ "$(sed -n 2p <<< "$lines_out")" == *"#3a0000"* ]]
	[ "$(grep -c 'dropdown=false' <<< "$lines_out")" -eq 2 ]
	# The panel drops the attributes of a line's first markup element, so the
	# colour must not live there or the T renders white in both frames and
	# nothing flashes. Verified by sampling the rendered pixels.
	[ "$(grep -c '^<tt> </tt><tt><span color=' <<< "$lines_out")" -eq 2 ]
}

@test "a pending tap outranks a copy that has not finished flashing" {
	touch "$BLINK"
	touch "$TOUCH"
	run "$APPLET"
	[ "$status" -eq 0 ]
	# Yellow says "done, go paste". Showing it while the key is still waiting
	# would say the copy landed when nothing has been read yet.
	[[ "$(button_lines "$output")" == *"#ff3b30"* ]]
	[[ "$(button_lines "$output")" != *"🟡"* ]]
}

@test "a tap cue left behind by a killed picker expires" {
	# touch_cue_on traps EXIT, but a kill -9 runs no trap. Without a ceiling the
	# T would sit there asking for a touch nobody owes.
	touch -d "@$(($(date +%s) - 121))" "$TOUCH"
	run "$APPLET"
	[ "$status" -eq 0 ]
	[ "$(wc -l <<< "$(button_lines "$output")")" -eq 1 ]
	[[ "$(button_lines "$output")" == *"🔑"* ]]
	[ ! -f "$TOUCH" ]
}

@test "picker and applet name the same marker files" {
	local marker
	for marker in secret-picker-blink secret-picker-touch; do
		grep -q "$marker" "$PICKER"
		grep -q "$marker" "$APPLET"
	done
	# Same directory too, or the picker writes where nothing is watching.
	grep -q 'XDG_RUNTIME_DIR:-/run/user/\$UID' "$PICKER"
	grep -q 'XDG_RUNTIME_DIR:-/run/user/\$UID' "$APPLET"
}

@test "the tap cue is cleared even when the read fails" {
	# `fail` exits from inside the wait, so the on/off pair is not enough on its
	# own: the trap is what clears the T after a missed touch.
	run bash -c "sed -n '/^touch_cue_on()/,/^}/p' '$PICKER'"
	[[ "$output" == *"trap 'rm -f \"\$TOUCH_CUE\"' EXIT"* ]]
}

@test "the copy path sends no notification" {
	# The whole point of the blink. A notify-send here would put the secret's
	# name on screen for five seconds after the copy.
	run bash -c "sed -n '/^copy)/,/^\t;;/p' '$PICKER'"
	[ -n "$output" ]
	[[ "$output" == *"blink_key"* ]]
	# The tap cue is now the badge too, raised before the read blocks.
	[[ "$output" == *"touch_cue_on"* ]]
	[[ "$output" != *"notify-send"* ]]
	run bash -c "sed -n '/^copy)/,/^\t;;/p' '$PICKER' | grep -c 'note \"'"
	[ "$output" -eq 0 ]
}

@test "only errors and state changes still notify" {
	# note() and fail() are the two that survive. A third notify-send anywhere
	# else means a cue crept back in.
	run bash -c "grep -c 'notify-send' '$PICKER'"
	[ "$output" -eq 2 ]
	# Demote reads the secret out of the bastion, so it waits on a tap the same
	# way a copy does and gets the same T.
	run bash -c "sed -n '/^demote)/,/^\t;;/p' '$PICKER'"
	[[ "$output" == *"touch_cue_on"* ]]
	[[ "$output" != *"notify-send"* ]]
}
