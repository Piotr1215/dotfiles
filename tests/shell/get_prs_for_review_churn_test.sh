#!/usr/bin/env bash
# Guards the completion pass of __get_prs_for_review.sh against search flakiness.
#
# The bug this pins: main() completed every pending PR task missing from one
# GitHub search, then ran a second search to create tasks. Search sometimes
# returns a partial result set without an error, so the two calls disagreed and
# each run completed and recreated about 50 tasks. vcluster#4192 alone collected
# 75 completed duplicates, and open review requests kept vanishing from the board.
# The fix fetches once and completes a task only when its PR is no longer open.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_data="$(mktemp -d /tmp/get-prs-churn-test.XXXXXX)"
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
	[ -z "$url" ] || task "$uuid" annotate -- "$url" >/dev/null 2>&1
}

add_pr_task "still open, dropped by search (#201)" "https://github.com/loft-sh/demo/pull/201"
add_pr_task "merged (#202)" "https://github.com/loft-sh/demo/pull/202"
add_pr_task "no url annotation (#203)" ""
add_pr_task "listed by search (#204)" "https://github.com/loft-sh/demo/pull/204"
add_pr_task "state unreadable (#205)" "https://github.com/loft-sh/demo/pull/205"

# Load the script's functions without running main, which would hit GitHub.
# shellcheck disable=SC1090
source <(sed 's/^main$//' "$repo_root/scripts/__get_prs_for_review.sh")

calls="$test_data/search-calls"
: >"$calls"

# A partial search result: only 204 comes back, although 201 is still open.
get_review_prs() {
	echo x >>"$calls"
	echo '[{"title":"listed by search","number":204,"url":"https://github.com/loft-sh/demo/pull/204","repository":{"name":"demo"},"createdAt":"2026-10-01T00:00:00Z","updatedAt":"2026-10-01T00:00:00Z"}]'
}
get_approved_prs() { echo '[]'; }

gh() {
	case "$3" in
	*/201) echo OPEN ;;
	*/202) echo MERGED ;;
	*/205) return 1 ;;
	*) echo OPEN ;;
	esac
}

main >/dev/null

pending() {
	task status:pending project:pr-reviews export |
		jq -e --arg d "$1" 'any(.[]; .description == $d)' >/dev/null
}

[ "$(wc -l <"$calls")" -eq 1 ] ||
	fail "main searched GitHub $(wc -l <"$calls") times, it must reuse one snapshot"

pending "still open, dropped by search (#201)" ||
	fail "an open PR missing from a partial search was completed, the churn bug is back"

! pending "merged (#202)" ||
	fail "a merged PR missing from search was left pending"

! pending "no url annotation (#203)" ||
	fail "a task with no PR URL missing from search was left pending"

pending "listed by search (#204)" ||
	fail "a PR returned by search was completed"

pending "state unreadable (#205)" ||
	fail "a PR whose state could not be read was completed, it must fail closed"

count=$(task status:pending project:pr-reviews export | jq 'length')
[ "$count" -eq 3 ] ||
	fail "expected 3 pending PR tasks and no duplicates, found $count"

# A second run against the same state must complete nothing and create nothing.
output=$(main | grep -E 'Marking task as done|Creating new task' || true)
[ -z "$output" ] ||
	fail "a second run was not a no-op, it printed: $output"

if [ "$failures" -eq 0 ]; then
	echo "PASS: get_prs_for_review completion pass survives partial search"
else
	exit 1
fi
