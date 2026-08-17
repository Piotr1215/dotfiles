#!/usr/bin/env bats
# Covers the four blocks the standup pane feeds into the bot in
# #engineering-enablement-private: their order, the day window question 1 asks
# for, and the empty-versus-broken distinction that kept the old chain's death
# invisible.

setup() {
	ANSWERS="${BATS_TEST_DIRNAME}/../../scripts/__standup_answers.sh"
	TMPDIR_TEST="$(mktemp -d)"
	STUBS="${TMPDIR_TEST}/stubs"
	STATE_DIR="${TMPDIR_TEST}/state"
	mkdir -p "$STUBS"

	# Never let a test read or write the real saved answers.
	export STANDUP_STATE_DIR="$STATE_DIR"

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

@test "yesterday's stated focus is recalled above today's completions" {
	mkdir -p "$STATE_DIR"
	command cat >"${STATE_DIR}/2026-08-14.md" <<'EOF'
1. What did you accomplish yesterday?

- [x] older work

----------------

2. What are focusing on today?

PKCE hardening, and the argocd credential

----------------

3. Do you have any blockers?
EOF

	run env STANDUP_DOW=2 STANDUP_STATE_DIR="$STATE_DIR" "$ANSWERS"
	[ "$status" -eq 0 ]
	[[ "$output" == *"On 2026-08-14 you said you would focus on:"* ]]
	[[ "$output" == *"PKCE hardening, and the argocd credential"* ]]
	[[ "$output" == *"Completed since:"* ]]
}

@test "the recall stops at the section end rather than swallowing question three" {
	mkdir -p "$STATE_DIR"
	command cat >"${STATE_DIR}/2026-08-14.md" <<'EOF'
2. What are focusing on today?

the one thing

----------------

3. Do you have any blockers?

a blocker that must not be recalled as focus
EOF

	run env STANDUP_DOW=2 STANDUP_STATE_DIR="$STATE_DIR" "$ANSWERS"
	[[ "$output" == *"the one thing"* ]]
	[[ "$output" != *"a blocker that must not be recalled as focus"* ]]
}

@test "today's own file is not recalled as yesterday's" {
	mkdir -p "$STATE_DIR"
	command cat >"${STATE_DIR}/$(date +%F).md" <<'EOF'
2. What are focusing on today?

written earlier today
EOF

	run env STANDUP_DOW=2 STANDUP_STATE_DIR="$STATE_DIR" "$ANSWERS"
	[[ "$output" != *"written earlier today"* ]]
	[[ "$output" != *"you said you would focus on"* ]]
}

@test "a heavily edited file with the heading gone recalls nothing rather than guessing" {
	mkdir -p "$STATE_DIR"
	printf 'just some prose I typed over everything\n' >"${STATE_DIR}/2026-08-14.md"

	run env STANDUP_DOW=2 STANDUP_STATE_DIR="$STATE_DIR" "$ANSWERS"
	[ "$status" -eq 0 ]
	[[ "$output" != *"you said you would focus on"* ]]
	[[ "$output" != *"just some prose"* ]]
}

@test "no previous answer at all is not an error" {
	run env STANDUP_DOW=2 STANDUP_STATE_DIR="${TMPDIR_TEST}/never-written" "$ANSWERS"
	[ "$status" -eq 0 ]
	[[ "$output" == *"1. What did you accomplish yesterday?"* ]]
	[[ "$output" != *"you said you would focus on"* ]]
}

@test "edit mode saves what is left in the buffer, not what was generated" {
	command -v nvim >/dev/null || skip "nvim not installed"
	mkdir -p "$STATE_DIR"

	# nvim runs -c commands in the order given, so a quit appended by the
	# caller would fire before the capture autocmd is registered. The wrapper
	# slips it in ahead of the trailing '-' instead, which is the only way to
	# drive the real editor to completion without a terminal.
	#
	# q! and not wq!: the buffer is nofile, so a write fails with E382 and
	# headless nvim then waits forever with nobody to answer it. Discarding is
	# also what the real q mapping does, which is the case worth covering.
	#
	# setline and not `normal! i`, for the same reason in a different disguise:
	# an insert-mode normal command leaves the editor in insert mode, and the
	# process outlives the test even though the capture already fired. bats
	# waits on it and the whole suite hangs at the end.
	command cat >"${TMPDIR_TEST}/ed" <<'EOF'
#!/usr/bin/env bash
args=("$@")
last="${args[-1]}"
unset 'args[-1]'
exec nvim --headless "${args[@]}" -c '%delete _' -c "call setline(1, 'I rewrote all of it')" -c 'q!' "$last"
EOF
	chmod +x "${TMPDIR_TEST}/ed"

	run env STANDUP_DOW=2 STANDUP_STATE_DIR="$STATE_DIR" \
		STANDUP_EDITOR_CMD="${TMPDIR_TEST}/ed" "$ANSWERS" --edit
	[ "$status" -eq 0 ]

	run command cat "${STATE_DIR}/$(date +%F).md"
	[[ "$output" == *"I rewrote all of it"* ]]
	[[ "$output" != *"1. What did you accomplish yesterday?"* ]]
}

@test "an unknown argument fails loudly instead of printing a report" {
	run env STANDUP_DOW=2 "$ANSWERS" --weekly
	[ "$status" -eq 1 ]
	[[ "$output" == *"Unknown argument"* ]]
}
