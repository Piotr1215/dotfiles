#!/usr/bin/env bats
#
# Covers .config/argos/voice-line.1s.sh, the panel flash that names the agent a
# spoken line reached. Failures to guard: a marker that keeps flashing after its
# window, a single button line (argos cycles only two or more, so nothing would
# flash), a colour on the line's first markup element, which the panel drops, an
# idle applet that shows its file name instead of hiding, and the relay drifting
# onto another marker path, which would leave a delivered line looking lost.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	APPLET="$REPO_ROOT/.config/argos/voice-line.1s.sh"
	export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
	mkdir -p "$XDG_RUNTIME_DIR"
	MARKER="$XDG_RUNTIME_DIR/voice-mode-delivered"
}

@test "with no delivery the applet hides" {
	run bash "$APPLET"
	[ "$status" -eq 0 ]
	[ "$output" = "---" ]
}

@test "a fresh delivery flashes the agent's name on two different lines" {
	printf 'klod2' >"$MARKER"
	run bash "$APPLET"
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 2 ]
	[[ "${lines[0]}" == *">klod2<"* ]]
	[[ "${lines[1]}" == *">klod2<"* ]]
	[ "${lines[0]}" != "${lines[1]}" ]
}

@test "the colour never sits on the first markup element" {
	printf 'klod2' >"$MARKER"
	run bash "$APPLET"
	[[ "${lines[0]}" == "<tt><b>V:</b></tt><tt><span color="* ]]
	[[ "${lines[1]}" == "<tt><b>V:</b></tt><tt><span color="* ]]
}

@test "the flash opens no menu" {
	printf 'klod2' >"$MARKER"
	run bash "$APPLET"
	[[ "${lines[0]}" == *" dropdown=false" ]]
	[[ "${lines[1]}" == *" dropdown=false" ]]
}

@test "the flash still runs inside its window" {
	printf 'klod2' >"$MARKER"
	touch -d '-3 seconds' "$MARKER"
	run bash "$APPLET"
	[ "${#lines[@]}" -eq 2 ]
}

@test "the flash stops once its window has passed" {
	printf 'klod2' >"$MARKER"
	touch -d '-5 seconds' "$MARKER"
	run bash "$APPLET"
	[ "$status" -eq 0 ]
	[ "$output" = "---" ]
}

@test "the relay writes the marker the applet reads" {
	grep -q "'voice-mode-delivered'" "$REPO_ROOT/scripts/__voice_mode.py"
	grep -q '/voice-mode-delivered"' "$APPLET"
}
