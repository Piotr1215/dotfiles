#!/usr/bin/env bats
# Covers the split of open authored PRs by who the ball is with, which is what
# lets the standup answer "blockers" and "hand off" from the same data instead
# of dumping one undifferentiated list into both.

setup() {
	PRS="${BATS_TEST_DIRNAME}/../../scripts/__get_my_pending_prs.sh"
	TMPDIR_TEST="$(mktemp -d)"
	FIXTURE="${TMPDIR_TEST}/prs.json"
	export PENDING_PRS_FIXTURE="$FIXTURE"

	# Ages are relative to now so the sort and the day count stay meaningful
	# whenever this runs. A literal date would age into a different assertion.
	local old recent mid ancient
	old="$(date -u -d '16 days ago' +%Y-%m-%dT%H:%M:%SZ)"
	recent="$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)"
	mid="$(date -u -d '6 days ago' +%Y-%m-%dT%H:%M:%SZ)"
	ancient="$(date -u -d '179 days ago' +%Y-%m-%dT%H:%M:%SZ)"

	command cat >"$FIXTURE" <<EOF
[
 {"number":177,"title":"stale review","url":"https://x/177","isDraft":false,"reviewDecision":"REVIEW_REQUIRED","createdAt":"$old","repository":{"nameWithOwner":"loft-sh/ai-skills"}},
 {"number":83,"title":"fresh review","url":"https://x/83","isDraft":false,"reviewDecision":"REVIEW_REQUIRED","createdAt":"$recent","repository":{"nameWithOwner":"loft-sh/ai-agents"}},
 {"number":624,"title":"approved, merge it","url":"https://x/624","isDraft":false,"reviewDecision":"APPROVED","createdAt":"$mid","repository":{"nameWithOwner":"loft-sh/loft-prod"}},
 {"number":1510,"title":"changes asked","url":"https://x/1510","isDraft":false,"reviewDecision":"CHANGES_REQUESTED","createdAt":"$ancient","repository":{"nameWithOwner":"loft-sh/vcluster-pro"}},
 {"number":9,"title":"a draft","url":"https://x/9","isDraft":true,"reviewDecision":null,"createdAt":"$recent","repository":{"nameWithOwner":"loft-sh/x"}}
]
EOF
}

teardown() {
	rm -rf "$TMPDIR_TEST"
}

@test "review pending means someone else has the ball" {
	run "$PRS" blocked
	[ "$status" -eq 0 ]
	[[ "$output" == *"stale review"* ]]
	[[ "$output" == *"fresh review"* ]]
	[[ "$output" != *"approved, merge it"* ]]
	[[ "$output" != *"changes asked"* ]]
}

@test "approved and changes-requested mean you have the ball" {
	run "$PRS" mine
	[ "$status" -eq 0 ]
	[[ "$output" == *"approved, merge it"* ]]
	[[ "$output" == *"changes asked"* ]]
	[[ "$output" != *"stale review"* ]]
}

@test "a draft is waiting on nobody, so it lands in neither bucket" {
	run "$PRS" blocked
	[[ "$output" != *"a draft"* ]]
	run "$PRS" mine
	[[ "$output" != *"a draft"* ]]
}

@test "oldest first, because age is what separates noise from a blocker" {
	run "$PRS" blocked
	[ "$(printf '%s\n' "$output" | head -1)" != "" ]
	[[ "$(printf '%s\n' "$output" | head -1)" == *"stale review"* ]]
	[[ "$(printf '%s\n' "$output" | tail -1)" == *"fresh review"* ]]
}

@test "each line carries its age in days" {
	run "$PRS" blocked
	[[ "$output" == *"(16d)"* ]]
	[[ "$output" == *"(2d)"* ]]
}

@test "changes requested is called out, since it reads as approved otherwise" {
	run "$PRS" mine
	[[ "$output" == *"changes requested"* ]]
}

@test "no argument groups both buckets under headings" {
	run "$PRS"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Waiting on someone else"* ]]
	[[ "$output" == *"Waiting on you"* ]]
}

@test "an unknown mode fails rather than silently printing nothing" {
	run "$PRS" everything
	[ "$status" -eq 1 ]
	[[ "$output" == *"Unknown mode"* ]]
}

@test "a github error is not mistaken for an empty PR list" {
	printf '%s\n' '{"message": "No server is currently available to service your request."}' >"$FIXTURE"
	run "$PRS" blocked
	[ "$status" -eq 1 ]
	[[ "$output" == *"Could not read open PRs"* ]]
}

@test "an empty response is an error too, not zero PRs" {
	: >"$FIXTURE"
	run "$PRS" blocked
	[ "$status" -eq 1 ]
	[[ "$output" == *"Could not read open PRs"* ]]
}

@test "genuinely zero open PRs is not an error" {
	printf '%s\n' '[]' >"$FIXTURE"
	run "$PRS" blocked
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}
