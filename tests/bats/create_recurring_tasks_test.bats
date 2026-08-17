#!/usr/bin/env bats
# Covers the boot-time task creation, and the standup task in particular: the
# schedule it honours, the session UDA that makes it open a tmux session rather
# than just remind, and the guard that keeps a second boot from adding it twice.

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

# Run the creator on a chosen weekday with a chosen standup schedule.
run_on() {
	local weekday="$1" days="${2:-1 2 3 4 5}"

	command cat >"${STUB_BIN}/date" <<EOF
#!/usr/bin/env bash
case "\$1" in
+%u) echo "$weekday" ;;
+%d) echo "15" ;;
*) exec /usr/bin/date "\$@" ;;
esac
EOF
	chmod +x "${STUB_BIN}/date"

	run env PATH="${STUB_BIN}:$PATH" STANDUP_DAYS="$days" "$CREATE"
}

added_standup() {
	grep -q 'add .*fill standup' "$TASK_LOG"
}

@test "adds the standup task on a scheduled day" {
	run_on 2
	[ "$status" -eq 0 ]
	run added_standup
	[ "$status" -eq 0 ]
}

@test "the standup task carries the session that opens the tmux session" {
	run_on 2
	run grep -h 'fill standup' "$TASK_LOG"
	[[ "$output" == *"session:standup"* ]]
	[[ "$output" == *"project:admin"* ]]
	[[ "$output" == *"tags:work,kill"* ]]
}

@test "honours a narrower schedule" {
	run_on 2 "1 3 5"
	run added_standup
	[ "$status" -ne 0 ]

	run_on 3 "1 3 5"
	run added_standup
	[ "$status" -eq 0 ]
}

@test "adds nothing at the weekend" {
	run_on 6
	[ "$status" -eq 0 ]
	run added_standup
	[ "$status" -ne 0 ]
	[[ "$output" != *"fill standup"* ]]
}

@test "a second boot on the same day does not add it twice" {
	EXISTING_COUNT=1 run_on 2
	[ "$status" -eq 0 ]
	run added_standup
	[ "$status" -ne 0 ]
}

@test "the thursday eng presentation survives alongside the standup" {
	run_on 4
	run grep -c 'add ' "$TASK_LOG"
	run grep -h 'fill eng presentation' "$TASK_LOG"
	[ "$status" -eq 0 ]
	run added_standup
	[ "$status" -eq 0 ]
}

@test "the daily tasks are untouched by the standup change" {
	run_on 2
	for description in "fill daily hours" "check notifications" "respond to slack messages"; do
		run grep -q "add .*${description}" "$TASK_LOG"
		[ "$status" -eq 0 ]
	done
}
