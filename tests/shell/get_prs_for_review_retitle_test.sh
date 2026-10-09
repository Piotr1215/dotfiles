#!/usr/bin/env bash
# Guards __get_prs_for_review.sh against duplicating a task when a PR is retitled.
#
# The bug this pins: main() looked tasks up by "title (#number)" only. A retitled
# PR no longer matched its task, so the sync created a second one, and the old
# task survived because its PR was still open. Renovate retitles on every version
# bump, so github-actions#289 collected four tasks; five PRs were duplicated on
# 2026-10-09. The fix finds the task by its PR URL and renames it.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_data="$(mktemp -d /tmp/get-prs-retitle-test.XXXXXX)"
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
		rc.verbose=nothing rc.context=none "$@"
}
export -f task

add_pr_task() {
	local desc="$1" url="$2" uuid
	task add project:pr-reviews +pr "$desc" >/dev/null 2>&1
	uuid=$(task status:pending project:pr-reviews export |
		jq -r --arg d "$desc" '.[] | select(.description == $d) | .uuid')
	task "$uuid" annotate -- "$url" >/dev/null 2>&1
	task "$uuid" modify "new_activity:2026-10-01T00:00:00Z" >/dev/null 2>&1
}

add_pr_task "chore(deps): update dependency renovate to v44.147.0 (#289)" "https://github.com/loft-sh/demo/pull/289"
add_pr_task "unchanged title (#290)" "https://github.com/loft-sh/demo/pull/290"

# Load the script's functions without running main, which would hit GitHub.
# shellcheck disable=SC1090
source <(sed 's/^main$//' "$repo_root/scripts/__get_prs_for_review.sh")

# 289 was retitled by a version bump; 290 kept its title.
get_review_prs() {
	echo '[
	{"title":"chore(deps): update dependency renovate to v44.148.4","number":289,"url":"https://github.com/loft-sh/demo/pull/289","repository":{"name":"demo"},"createdAt":"2026-09-24T00:00:00Z","updatedAt":"2026-10-01T00:00:00Z"},
	{"title":"unchanged title","number":290,"url":"https://github.com/loft-sh/demo/pull/290","repository":{"name":"demo"},"createdAt":"2026-09-24T00:00:00Z","updatedAt":"2026-10-01T00:00:00Z"}
	]'
}
get_approved_prs() { echo '[]'; }
gh() { echo OPEN; }

main >/dev/null

tasks_for() {
	task status:pending project:pr-reviews export |
		jq --arg u "$1" '[.[] | select(any(.annotations[]?; .description == $u))] | length'
}

pending() {
	task status:pending project:pr-reviews export |
		jq -e --arg d "$1" 'any(.[]; .description == $d)' >/dev/null
}

[ "$(tasks_for https://github.com/loft-sh/demo/pull/289)" -eq 1 ] ||
	fail "a retitled PR has $(tasks_for https://github.com/loft-sh/demo/pull/289) tasks, it must keep exactly one"

pending "chore(deps): update dependency renovate to v44.148.4 (#289)" ||
	fail "the retitled PR's task was not renamed to the live title"

! pending "chore(deps): update dependency renovate to v44.147.0 (#289)" ||
	fail "the stale title is still pending"

pending "unchanged title (#290)" ||
	fail "a PR with an unchanged title lost its task"

count=$(task status:pending project:pr-reviews export | jq 'length')
[ "$count" -eq 2 ] ||
	fail "expected 2 pending PR tasks, found $count"

# A second run against the same state must change nothing.
output=$(main | grep -E 'Marking task as done|Creating new task|retitled' || true)
[ -z "$output" ] ||
	fail "a second run was not a no-op, it printed: $output"

if [ "$failures" -eq 0 ]; then
	echo "PASS: get_prs_for_review keeps one task across a PR retitle"
else
	exit 1
fi
