#!/usr/bin/env bash
# Guards the both-directions reconciliation of +pr_approved.
#
# The bug this pins: update_approved_status used to only ADD the tag. GitHub
# dismisses an approval when a reviewer requests changes, so a PR that had been
# approved kept the tag forever and went on rendering as approved while it was
# actually waiting on work. The remove half is the fix, and it is the half a
# future refactor is most likely to drop, because nothing else in the script
# removes a tag.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_data="$(mktemp -d /tmp/get-prs-approved-test.XXXXXX)"
trap 'rm -rf "$test_data"' EXIT
export TASKRC="$repo_root/.taskrc"

failures=0

fail() {
	echo "FAIL: $1" >&2
	failures=$((failures + 1))
}

# Every taskwarrior call in the script routes through this, so the test never
# touches the real task database.
task() {
	command task rc.data.location="$test_data" rc.hooks=off rc.confirmation=off \
		rc.verbose=nothing "$@"
}
export -f task

task add project:pr-reviews +pr +pr_approved "still approved (#101)" >/dev/null 2>&1
task add project:pr-reviews +pr +pr_approved "approval dismissed (#102)" >/dev/null 2>&1
task add project:pr-reviews +pr "never approved (#103)" >/dev/null 2>&1

# Load the script's functions without running main, which would hit GitHub.
# shellcheck disable=SC1090
source <(sed 's/^main$//' "$repo_root/scripts/__get_prs_for_review.sh")

# Live approval state: only 101 is still approved. 102 has been dismissed and
# so has dropped out of the --review approved query, exactly as GitHub reports
# it after a changes-requested review.
get_approved_prs() {
	echo '[{"title":"still approved","number":101,"url":"https://example.invalid/101"}]'
}

update_approved_status >/dev/null

has_tag() {
	task "$1" export | jq -e 'any(.[]; (.tags // []) | index("pr_approved"))' >/dev/null 2>&1
}

uuid_for() {
	task status:pending project:pr-reviews export |
		jq -r --arg d "$1" '.[] | select(.description == $d) | .uuid'
}

has_tag "$(uuid_for "still approved (#101)")" ||
	fail "a PR that is still approved lost its +pr_approved tag"

! has_tag "$(uuid_for "approval dismissed (#102)")" ||
	fail "a dismissed approval kept a stale +pr_approved tag, the add-only bug is back"

! has_tag "$(uuid_for "never approved (#103)")" ||
	fail "an unapproved PR gained +pr_approved"

# A second run must be a no-op, so the sync does not churn modified timestamps
# or reprint on every cron tick.
output=$(update_approved_status)
[ -z "$output" ] ||
	fail "a second run was not quiet, it printed: $output"

if [ "$failures" -eq 0 ]; then
	echo "PASS: get_prs_for_review approval reconciliation"
else
	exit 1
fi
