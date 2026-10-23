#!/usr/bin/env bash
# PROJECT: pr-merge
# Follows every check on a merged PR's merge commit: GitHub Actions jobs,
# Spacelift tracked runs and any other app's check runs, plus commit statuses.
# Opens a floating tmux pane that polls them. The pane closes itself once every
# check has passed; a failed check keeps it open until q. A Spacelift run that
# waits for confirmation keeps it open with a ;;spacelift hint.
# The ;;merge picker (__pr_merge_pick.sh) chains this after `gh pr merge`.
#
# Usage: __pr_merge_watch.sh <owner/repo> <pr-number>
#        __pr_merge_watch.sh --follow <owner/repo> <pr-number> <sha>   (the pane)
#
# Env: PR_MERGE_WATCH_INTERVAL (10s between polls), PR_MERGE_WATCH_LINGER (3s
# before a passed or empty watch closes), PR_MERGE_WATCH_NO_RUNS (180s without
# any check before the watch gives up).
set -eo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
INTERVAL="${PR_MERGE_WATCH_INTERVAL:-10}"
LINGER="${PR_MERGE_WATCH_LINGER:-3}"
NO_RUNS="${PR_MERGE_WATCH_NO_RUNS:-180}"

# Check runs and commit statuses as one list of {state, name, detail}, state
# one of running, confirm (a Spacelift run awaiting confirmation), ok or fail.
# shellcheck disable=SC2016 # jq program, not shell
CHECKS_JQ='def flat: gsub("[\t\r\n]+"; " ");
[($runs.check_runs // [])[] | (.output.title // "" | flat) as $title | {name, detail: $title,
   state: (if .status != "completed" then (if ($title | test("awaiting confirmation"; "i")) then "confirm" else "running" end)
           elif .conclusion == "success" or .conclusion == "skipped" or .conclusion == "neutral" then "ok"
           else "fail" end)}]
+ [($status.statuses // [])[] | {name: .context, detail: (.description // "" | flat),
   state: (if .state == "pending" then "running" elif .state == "success" then "ok" else "fail" end)}]'
# none, fail, confirm, running or ok for the whole commit.
STATE_JQ='if length == 0 then "none"
elif any(.[]; .state == "fail") then "fail"
elif any(.[]; .state == "confirm") then "confirm"
elif any(.[]; .state == "running") then "running"
else "ok" end'
ROWS_JQ='.[] | [.state, .name, .detail] | join("\t")'

usage() {
	echo "Usage: __pr_merge_watch.sh <owner/repo> <pr-number>" >&2
	exit 1
}

valid_repo() { [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; }

# Block until q, or until stdin closes.
wait_for_q() {
	local key
	while read -rsn1 key; do [[ "$key" == q ]] && return 0; done
	return 0
}

# Every check on <sha> as CHECKS_JQ's list. A failed read counts as no checks.
checks() {
	local runs status
	runs=$(gh api "repos/$1/commits/$2/check-runs?per_page=100" 2>/dev/null) || runs='{}'
	status=$(gh api "repos/$1/commits/$2/status" 2>/dev/null) || status='{}'
	jq -n --argjson runs "$runs" --argjson status "$status" "$CHECKS_JQ" 2>/dev/null || echo '[]'
}

# Poll the checks on <sha> until they settle. Green on two polls in a row
# closes, so a check created a few seconds after the others is not missed.
follow() {
	local repo=$1 pr=$2 sha=$3 json state key green=0 start=$SECONDS
	while :; do
		json=$(checks "$repo" "$sha")
		state=$(jq -r "$STATE_JQ" <<<"$json")
		printf '\033[H\033[2J%s#%s  %s  %s   (q closes)\n\n' "$repo" "$pr" "${sha:0:7}" "$state"
		jq -r "$ROWS_JQ" <<<"$json" | column -t -s $'\t'
		case "$state" in
		ok)
			if ((++green >= 2)); then
				printf '\nAll checks passed, closing.\n'
				sleep "$LINGER"
				return 0
			fi
			;;
		fail)
			printf '\nA check failed. q closes.\n'
			wait_for_q
			return 1
			;;
		none)
			green=0
			if ((SECONDS - start >= NO_RUNS)); then
				printf 'No checks started for %s, closing.\n' "${sha:0:7}"
				sleep "$LINGER"
				return 0
			fi
			;;
		confirm)
			green=0
			printf '\nA Spacelift run waits for confirmation: type ;;spacelift.\n'
			;;
		*) green=0 ;;
		esac
		# Doubles as the poll interval. A closed stdin returns at once, so sleep.
		if read -rsn1 -t "$INTERVAL" key; then
			[[ "$key" == q ]] && return 0
		elif (($? <= 128)); then
			sleep "$INTERVAL"
		fi
	done
}

if [[ "${1:-}" == "--follow" ]]; then
	if ! valid_repo "${2:-}" || [[ ! "${3:-}" =~ ^[0-9]+$ || ! "${4:-}" =~ ^[0-9a-f]{40}$ ]]; then
		usage
	fi
	follow "$2" "$3" "$4"
	exit
fi

repo="${1:-}"
pr="${2:-}"
if ! valid_repo "$repo" || [[ ! "$pr" =~ ^[0-9]+$ ]]; then
	usage
fi

sha=$(gh pr view "$pr" --repo "$repo" --json mergeCommit | jq -r '.mergeCommit.oid // empty')
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
	echo "$repo#$pr has no merge commit yet" >&2
	exit 1
fi

# Outside tmux there is nowhere to float a pane: print the checks once instead.
if [[ -z "${TMUX:-}" ]]; then
	checks "$repo" "$sha" | jq -r "$ROWS_JQ" | column -t -s $'\t'
	exit 0
fi
tmux new-pane -d -x 90% -y 30% -X 5% -Y 2 ${TMUX_PANE:+-t "$TMUX_PANE"} \
	"$SELF --follow $repo $pr $sha"
echo "Watching checks for $repo#$pr (${sha:0:7}) in a floating pane; it closes when they pass."
