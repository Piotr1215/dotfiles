#!/usr/bin/env bats
#
# Covers __notify_actionable.sh, whose two failure modes are both silent:
# an action keyed "default" that never draws a button, and an unbounded wait
# that leaks one blocked process per ignored notification.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	NOTIFY="$REPO_ROOT/scripts/__notify_actionable.sh"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$STUB_BIN"
	RAN="$BATS_TEST_TMPDIR/ran"
	ARGS="$BATS_TEST_TMPDIR/dunstify.args"

	cat > "$STUB_BIN/handler" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$RAN"
EOF
	chmod +x "$STUB_BIN/handler"
	export PATH="$STUB_BIN:$PATH"
}

# $1 is what the stub prints as the user's response.
stub_dunstify() {
	cat > "$STUB_BIN/dunstify" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGS"
printf '%s' '$1'
EOF
	chmod +x "$STUB_BIN/dunstify"
}

@test "the action key is never the reserved 'default'" {
	# "default" means "the body was activated" and no server draws a button
	# for it, which is why the PR notification's action was invisible.
	stub_dunstify "act"
	run "$NOTIFY" critical Title Body "Press me" handler
	[ "$status" -eq 0 ]
	grep -q -- '--action=act,Press me' "$ARGS"
	! grep -q -- '--action=default' "$ARGS"
}

@test "clicking the button runs the command with its arguments" {
	stub_dunstify "act"
	run "$NOTIFY" critical Title Body "Press me" handler job-42 /state/dir
	[ "$status" -eq 0 ]
	[ "$(cat "$RAN")" = "job-42
/state/dir" ]
}

@test "dismissing the notification runs nothing" {
	stub_dunstify ""
	run "$NOTIFY" normal Title Body "Press me" handler
	[ "$status" -eq 0 ]
	[ ! -f "$RAN" ]
}

@test "a response that is not the action runs nothing" {
	stub_dunstify "2"
	run "$NOTIFY" normal Title Body "Press me" handler
	[ "$status" -eq 0 ]
	[ ! -f "$RAN" ]
}

@test "the wait is bounded so an ignored notification cannot leak a waiter" {
	# dunstify does not return when the popup expires: a 3s notification left
	# the waiter blocked twelve seconds later. Without the timeout this test
	# would hang instead of failing.
	cat > "$STUB_BIN/dunstify" <<'EOF'
#!/usr/bin/env bash
sleep 60
EOF
	chmod +x "$STUB_BIN/dunstify"
	NOTIFY_ACTION_WAIT_SEC=1 run timeout 15 "$NOTIFY" \
		normal Title Body "Press me" handler
	[ "$status" -eq 0 ]
	[ ! -f "$RAN" ]
}

@test "too few arguments is a usage error, not a silent no-op" {
	stub_dunstify "act"
	run "$NOTIFY" critical Title Body
	[ "$status" -eq 2 ]
}
