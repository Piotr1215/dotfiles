#!/usr/bin/env bash
# PROJECT: standup
# Open authored PRs, split by who the ball is with.
#
# The old undifferentiated list carried the header "not a real blocker, just
# some open PRs pending review", which was true of the list as a whole and
# false of half its entries. A PR that has sat in REVIEW_REQUIRED for a week is
# exactly a blocker; one that is APPROVED is not, it is waiting on you to press
# merge. Those are two different standup answers and they were in one pile.
#
# Age is printed because it is what separates the two cases within a state. A
# review requested this morning is not worth mentioning; the same PR eight days
# later is the whole answer to question three.
#
# Usage:
#   __get_my_pending_prs.sh            every open PR, grouped
#   __get_my_pending_prs.sh blocked    waiting on someone else (review pending)
#   __get_my_pending_prs.sh mine       waiting on you (approved, changes asked)

set -eo pipefail

# Tests point this at a fixture so the partition can be checked without GitHub.
PRS_FIXTURE="${PENDING_PRS_FIXTURE:-}"

# reviewDecision is the field the whole split turns on, and `gh search prs`
# cannot return it: its --json accepts only isDraft and state among the fields
# that matter here. One graphql call gets it for every PR at once, where the
# per-PR `gh pr view` alternative is one round trip each.
#
# GitHub's search backend returns sporadic 503s ("No server is currently
# available to service your request"), observed here failing two runs in three
# within a minute. So this retries, and the `|| true` matters as much as the
# retry: gh exits non-zero on a 503, and under `set -e` that killed the script
# inside the command substitution before the validation below could say a word.
# A silently empty PR list reads as "nothing open", which is the wrong answer to
# both standup questions.
fetch_prs() {
	if [[ -n "$PRS_FIXTURE" ]]; then
		command cat "$PRS_FIXTURE"
		return
	fi

	local attempt out
	for attempt in 1 2 3; do
		out="$(gh api graphql -f query='
		{
		  search(query: "author:@me org:loft-sh is:pr is:open", type: ISSUE, first: 50) {
		    nodes { ... on PullRequest {
		      number title url isDraft reviewDecision createdAt
		      repository { nameWithOwner }
		    } }
		  }
		}' --jq '.data.search.nodes' 2>&1 || true)"

		if printf '%s' "$out" | jq -e 'type == "array"' >/dev/null 2>&1; then
			printf '%s' "$out"
			return
		fi

		[[ "$attempt" -lt 3 ]] && sleep 2
	done

	printf '%s' "$out"
}

# A draft is waiting on nobody, so it is neither a blocker nor a handoff. It
# stays out of both buckets rather than inflating whichever one it lands in.
render() {
	local wanted="$1" prs="$2"

	printf '%s' "$prs" | jq -r --arg wanted "$wanted" '
		def bucket:
			if .isDraft then "draft"
			elif .reviewDecision == "REVIEW_REQUIRED" then "blocked"
			elif .reviewDecision == "APPROVED" or .reviewDecision == "CHANGES_REQUESTED" then "mine"
			else "draft" end;

		def age: ((now - (.createdAt | fromdateiso8601)) / 86400 | floor);

		[ .[] | select(bucket == $wanted) ]
		| sort_by(- age)
		| .[]
		| "- [ ] \(.title) [#\(.number)](\(.url)) (\(age)d\(if .reviewDecision == "CHANGES_REQUESTED" then ", changes requested" else "" end))"
	' 2>/dev/null
}

main() {
	local mode="${1:-all}"
	local prs
	prs="$(fetch_prs)"

	# A failed call does not return null, it returns GitHub's error object, so
	# emptiness is not the test. Seen in the wild: {"message": "No server is
	# currently available to service your request"}, which rendered as an empty
	# list and read as "no open PRs" rather than "could not ask".
	if ! printf '%s' "$prs" | jq -e 'type == "array"' >/dev/null 2>&1; then
		echo "Could not read open PRs from GitHub: ${prs:-empty response}" >&2
		exit 1
	fi

	case "$mode" in
	blocked) render blocked "$prs" ;;
	mine) render mine "$prs" ;;
	all)
		echo "Waiting on someone else"
		echo
		render blocked "$prs"
		echo
		echo "Waiting on you"
		echo
		render mine "$prs"
		;;
	*)
		echo "Unknown mode: $mode (expected blocked, mine, or no argument)" >&2
		exit 1
		;;
	esac
}

main "$@"
