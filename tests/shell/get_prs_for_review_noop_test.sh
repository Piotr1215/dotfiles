#!/usr/bin/env bash
# Guards __get_prs_for_review.sh against write churn and per-PR task lookups.
#
# The bug this pins: the sync ran `task export` several times per PR and always
# ran `task modify new_activity:...`, even when the value was unchanged. Each
# `task` call loads the whole 45k-task database (0.3 to 2s), so a run took 13
# minutes, and every write made the open taskwarrior-tui instances reload. The
# fix reads one export in memory and writes only when a value changes.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_data="$(mktemp -d /tmp/get-prs-noop-test.XXXXXX)"
trap 'rm -rf "$test_data"' EXIT
export TASKRC="$repo_root/.taskrc"

failures=0

fail() {
	echo "FAIL: $1" >&2
	failures=$((failures + 1))
}

# Logs every call, then runs against the scratch database. new-uuid keeps the
# "Created task <uuid>" line that create_task parses.
calls="$test_data/calls"
: >"$calls"
task() {
	echo "$*" >>"$calls"
	command task rc.data.location="$test_data" rc.hooks=off rc.confirmation=off \
		rc.verbose=new-uuid rc.context=none "$@"
}
export -f task

add_pr_task() {
	local desc="$1" url="$2" activity="$3" uuid
	command task rc.data.location="$test_data" rc.hooks=off rc.confirmation=off rc.verbose=nothing \
		add project:pr-reviews +pr "$desc" >/dev/null 2>&1
	uuid=$(command task rc.data.location="$test_data" rc.hooks=off rc.verbose=nothing status:pending project:pr-reviews export |
		jq -r --arg d "$desc" '.[] | select(.description == $d) | .uuid')
	command task rc.data.location="$test_data" rc.hooks=off rc.confirmation=off rc.verbose=nothing \
		"$uuid" annotate -- "$url" >/dev/null 2>&1
	command task rc.data.location="$test_data" rc.hooks=off rc.confirmation=off rc.verbose=nothing \
		"$uuid" modify "new_activity:$activity" >/dev/null 2>&1
}

add_pr_task "unchanged (#301)" "https://github.com/loft-sh/demo/pull/301" "2026-10-01T00:00:00Z"
add_pr_task "has news (#302)" "https://github.com/loft-sh/demo/pull/302" "2026-10-01T00:00:00Z"

# shellcheck disable=SC1090
source <(sed 's/^main$//' "$repo_root/scripts/__get_prs_for_review.sh")

get_review_prs() {
	echo '[
	{"title":"unchanged","number":301,"url":"https://github.com/loft-sh/demo/pull/301","repository":{"name":"demo"},"createdAt":"2026-09-24T00:00:00Z","updatedAt":"2026-10-01T00:00:00Z"},
	{"title":"has news","number":302,"url":"https://github.com/loft-sh/demo/pull/302","repository":{"name":"demo"},"createdAt":"2026-09-24T00:00:00Z","updatedAt":"2026-10-05T00:00:00Z"},
	{"title":"brand new","number":303,"url":"https://github.com/loft-sh/demo/pull/303","repository":{"name":"demo"},"createdAt":"2026-10-02T00:00:00Z","updatedAt":"2026-10-03T00:00:00Z"}
	]'
}
get_approved_prs() { echo '[]'; }
gh() { echo OPEN; }

: >"$calls"
main >/dev/null

has_call() { grep -q -- "$1" "$calls"; }

has_call "modify new_activity:2026-10-05T00:00:00Z +fresh" ||
	fail "a PR with new activity was not marked fresh"

! has_call "modify new_activity:2026-10-01T00:00:00Z" ||
	fail "an unchanged new_activity was rewritten"

pr303=$(command task rc.data.location="$test_data" rc.hooks=off rc.verbose=nothing status:pending project:pr-reviews export |
	jq -c '.[] | select(.description == "brand new (#303)")')
jq -e '(.new_activity | startswith("20261003")) and any(.annotations[]; .description == "https://github.com/loft-sh/demo/pull/303") and (.tags | index("kill") and index("work") and index("pr")) and ((.tags | index("fresh")) | not)' <<<"$pr303" >/dev/null ||
	fail "the new task lacks its new_activity, annotation or tags, or got +fresh"

# Steady state: three PRs, one export, no writes.
: >"$calls"
main >/dev/null
[ "$(wc -l <"$calls")" -eq 1 ] ||
	fail "an idle run made $(wc -l <"$calls") task calls, expected exactly 1 export"
! has_call modify || fail "an idle run wrote to the database"

if [ "$failures" -eq 0 ]; then
	echo "PASS: get_prs_for_review writes only on change and exports once"
else
	exit 1
fi
