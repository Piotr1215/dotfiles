#!/usr/bin/env bats
# Covers the boot-time task creation: the weekday gate, the Thursday extra, and
# the guard that keeps a second boot from adding the same day's tasks twice.
#
# Standup is deliberately absent. It is a standing task like meetings, created
# once and started whenever the standup happens, so nothing recreates it daily.

setup() {
	CREATE="${BATS_TEST_DIRNAME}/../../scripts/__create_recurring_tasks.sh"
	TMPDIR_TEST="$(mktemp -d)"
	STUB_BIN="${TMPDIR_TEST}/bin"
	mkdir -p "$STUB_BIN"

	TASK_LOG="${TMPDIR_TEST}/task.log"
	export TASK_LOG

	# The real script decides by `task ... count | grep -q 1`. EXISTING_COUNT
	# drives what the stub reports so both branches of that guard are reachable.
	command cat >"${STUB_BIN}/task" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TASK_LOG"
case "$*" in
*count*) printf '%s\n' "${EXISTING_COUNT:-0}" ;;
esac
exit 0
EOF
	chmod +x "${STUB_BIN}/task"
}

teardown() {
	rm -rf "$TMPDIR_TEST"
}

# Run the creator on a chosen weekday.
run_on() {
	local weekday="$1"

	command cat >"${STUB_BIN}/date" <<EOF
#!/usr/bin/env bash
case "\$1" in
+%u) echo "$weekday" ;;
+%d) echo "15" ;;
*) exec /usr/bin/date "\$@" ;;
esac
EOF
	chmod +x "${STUB_BIN}/date"

	run env PATH="${STUB_BIN}:$PATH" "$CREATE"
}

@test "adds the daily tasks on a weekday" {
	run_on 2
	[ "$status" -eq 0 ]

	local description
	for description in "fill daily hours" "check notifications" "respond to slack messages"; do
		run grep -q "add .*${description}" "$TASK_LOG"
		[ "$status" -eq 0 ]
	done
}

@test "adds nothing at the weekend" {
	run_on 6
	[ "$status" -eq 0 ]
	run grep -q 'add ' "$TASK_LOG"
	[ "$status" -ne 0 ]
}

@test "thursday brings the eng presentation" {
	run_on 4
	run grep -q 'add .*fill eng presentation' "$TASK_LOG"
	[ "$status" -eq 0 ]
}

@test "other weekdays leave the eng presentation alone" {
	run_on 3
	run grep -q 'fill eng presentation' "$TASK_LOG"
	[ "$status" -ne 0 ]
}

@test "a second boot on the same day does not add anything twice" {
	EXISTING_COUNT=1 run_on 2
	[ "$status" -eq 0 ]
	run grep -q 'add ' "$TASK_LOG"
	[ "$status" -ne 0 ]
}

@test "standup is not recreated here; it is a standing task" {
	run_on 2
	run grep -qi 'standup' "$TASK_LOG"
	[ "$status" -ne 0 ]
}
