#!/usr/bin/env bats

# __toggle_keep_top.sh sets "on top" as a pair, above and sticky, decided off
# the above flag alone. These pin that pairing, the --active path Super+Shift+T
# runs, and the picker path the zsh widget runs.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	SCRIPT="$REPO_ROOT/scripts/__toggle_keep_top.sh"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	export WMCTRL_LOG="$BATS_TEST_TMPDIR/wmctrl.log"
	mkdir -p "$STUB_BIN"
	export PATH="$STUB_BIN:$PATH"
	stub xdotool 'echo 4242'
	stub wmctrl 'echo "$*" >> "$WMCTRL_LOG"'
}

stub() {
	printf '#!/usr/bin/env bash\n%s\n' "$2" > "$STUB_BIN/$1"
	chmod +x "$STUB_BIN/$1"
}

@test "a window that is not on top gets above and sticky together" {
	stub xprop 'echo "_NET_WM_STATE(ATOM) = _NET_WM_STATE_FOCUSED"'
	run bash "$SCRIPT" --active
	[ "$status" -eq 0 ]
	[ "$(cat "$WMCTRL_LOG")" = "-i -r 4242 -b add,above,sticky" ]
}

@test "an on-top window loses both, even if sticky was never set" {
	stub xprop 'echo "_NET_WM_STATE(ATOM) = _NET_WM_STATE_ABOVE, _NET_WM_STATE_FOCUSED"'
	run bash "$SCRIPT" --active
	[ "$status" -eq 0 ]
	[ "$(cat "$WMCTRL_LOG")" = "-i -r 4242 -b remove,above,sticky" ]
}

@test "a sticky window that is not above is brought up, not inverted" {
	stub xprop 'echo "_NET_WM_STATE(ATOM) = _NET_WM_STATE_STICKY"'
	run bash "$SCRIPT" --active
	[ "$status" -eq 0 ]
	[ "$(cat "$WMCTRL_LOG")" = "-i -r 4242 -b add,above,sticky" ]
}

@test "the picked window is the one toggled" {
	stub wmctrl 'if [ "$1" = "-l" ]; then printf "0x01 0 host Term\n0x02 0 host Chrome\n"; else echo "$*" >> "$WMCTRL_LOG"; fi'
	stub xprop 'echo "_NET_WM_STATE(ATOM) = "'
	stub fzf-tmux 'grep Chrome'
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(cat "$WMCTRL_LOG")" = "-i -r 0x02 -b add,above,sticky" ]
}

@test "cancelling the picker changes nothing" {
	stub wmctrl 'if [ "$1" = "-l" ]; then echo "0x01 0 host Term"; else echo "$*" >> "$WMCTRL_LOG"; fi'
	stub xprop 'echo "_NET_WM_STATE(ATOM) = "'
	stub fzf-tmux 'cat >/dev/null; exit 130'
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ ! -e "$WMCTRL_LOG" ]
}
