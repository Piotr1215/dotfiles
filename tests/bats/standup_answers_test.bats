#!/usr/bin/env bats
# Covers the four blocks the standup pane feeds into the bot in
# #engineering-enablement-private: their order, the day window question 1 asks
# for, and the empty-versus-broken distinction that kept the old chain's death
# invisible.

setup() {
	ANSWERS="${BATS_TEST_DIRNAME}/../../scripts/__standup_answers.sh"
	TMPDIR_TEST="$(mktemp -d)"
	STUBS="${TMPDIR_TEST}/stubs"
	mkdir -p "$STUBS"

	export STANDUP_COMPLETED_CMD="${STUBS}/completed"
	export STANDUP_TASKS_CMD="${STUBS}/tasks"
	export STANDUP_PRS_CMD="${STUBS}/prs"

	stub "$STANDUP_COMPLETED_CMD" 0 "- [x] shipped the thing"
	stub "$STANDUP_TASKS_CMD" 0 "- [ ] doing the next thing"
	stub "$STANDUP_PRS_CMD" 0 "- [ ] a pull request"
}

teardown() {
	rm -rf "$TMPDIR_TEST"
}

# A stub that records its arguments and replays a fixed exit status and output.
# The PR command is called twice per run with different modes, so argv appends
# rather than overwrites.
stub() {
	local path="$1" status="$2" output="$3"

	command cat >"$path" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >>"${path}.argv"
printf '%s\n' "$output"
exit $status
EOF
	chmod +x "$path"
}

@test "prints the four questions in the order the bot asks them" {
	run env STANDUP_DOW=2 "$ANSWERS"
	[ "$status" -eq 0 ]

	local order
	order="$(printf '%s\n' "$output" | grep -n '^[1-4]\. ' | cut -d: -f2- | tr '\n' '|')"
	[ "$order" = "1. What did you accomplish yesterday?|2. What are focusing on today?|3. Do you have any blockers?|4. Anything to hand off?|" ]
}

@test "question one asks for a single day outside monday" {
	run env STANDUP_DOW=3 "$ANSWERS"
	[ "$status" -eq 0 ]
	run command cat "${STANDUP_COMPLETED_CMD}.argv"
	[ "$output" = "1" ]
}

@test "monday reaches back across the weekend to friday" {
	run env STANDUP_DOW=1 "$ANSWERS"
	[ "$status" -eq 0 ]
	run command cat "${STANDUP_COMPLETED_CMD}.argv"
	[ "$output" = "3" ]
}

@test "question two asks for the current filter, not a next tag nothing carries" {
	run env STANDUP_DOW=2 "$ANSWERS"
	[ "$status" -eq 0 ]
	run command cat "${STANDUP_TASKS_CMD}.argv"
	[ "$output" = "+current" ]
}

@test "an empty report says so rather than leaving a blank block" {
	stub "$STANDUP_COMPLETED_CMD" 0 ""
	run env STANDUP_DOW=2 "$ANSWERS"
	[ "$status" -eq 0 ]
	[[ "$output" == *"(nothing recorded)"* ]]
}

@test "whitespace-only output still counts as empty" {
	stub "$STANDUP_COMPLETED_CMD" 0 "   "
	run env STANDUP_DOW=2 "$ANSWERS"
	[[ "$output" == *"(nothing recorded)"* ]]
}

@test "a broken report is not reported as an empty one" {
	stub "$STANDUP_COMPLETED_CMD" 1 "Error: You need to install the JSON Perl module."
	run env STANDUP_DOW=2 "$ANSWERS"
	[ "$status" -eq 0 ]
	[[ "$output" == *"unavailable"* ]]
	[[ "$output" != *"(nothing recorded)"* ]]
}

@test "one broken report does not take the other blocks down with it" {
	stub "$STANDUP_PRS_CMD" 1 "gh: not authenticated"
	run env STANDUP_DOW=2 "$ANSWERS"
	[ "$status" -eq 0 ]
	[[ "$output" == *"shipped the thing"* ]]
	[[ "$output" == *"doing the next thing"* ]]
}

@test "the two typed questions still expect to be typed" {
	run env STANDUP_DOW=2 "$ANSWERS"
	[[ "$output" == *"3. Do you have any blockers?"* ]]
	[[ "$output" == *"(type this one"* ]]
}

@test "blockers ask for the PRs waiting on someone else, handoffs for those waiting on you" {
	run env STANDUP_DOW=2 "$ANSWERS"
	[ "$status" -eq 0 ]
	run command cat "${STANDUP_PRS_CMD}.argv"
	[ "$output" = "blocked
mine" ]
}

@test "a github outage shows on both PR questions rather than reading as no PRs" {
	stub "$STANDUP_PRS_CMD" 1 "Could not read open PRs from GitHub: 503"
	run env STANDUP_DOW=2 "$ANSWERS"
	[ "$status" -eq 0 ]
	[[ "$output" == *"PRs awaiting review unavailable"* ]]
	[[ "$output" == *"PRs waiting on you unavailable"* ]]
}

@test "an unknown argument fails loudly instead of printing a report" {
	run env STANDUP_DOW=2 "$ANSWERS" --weekly
	[ "$status" -eq 1 ]
	[[ "$output" == *"Unknown argument"* ]]
}
