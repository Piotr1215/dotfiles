#!/usr/bin/env bash
# PROJECT: pr-merge
# ;;merge picker. Lists the open PRs of the repo in the focused tmux pane in
# rofi, types a merge command for the pick, and opens the PR in the browser
# tiled beside the terminal, the way the ctrl+1 alacritty hint does.
#
# An agent pane lists the PRs its pr-watch watches instead (owner/repo#N rows),
# from every repo: agents often span repos, so the pane's own repo is the wrong
# list there. __lib_pr_watch_export.sh finds that list for Claude and Codex
# panes, running ones included; with no open PR in it, the pane's repo is listed.
#
# Typed as one line, no Enter, so nothing runs until you press it:
#   !gh pr merge <n> --repo <owner/repo> --<method> [--admin] && __pr_merge_watch.sh <owner/repo> <n>
# The leading ! runs it from a Claude Code prompt. __pr_merge_watch.sh opens a
# floating tmux pane that follows the workflow runs on the merge commit.
#
# --admin (bypass branch protection) is added when the checks pass and the merge
# is still blocked, typically by a missing review. While the checks still run,
# the typed line first waits for them and merges only if they all pass:
#   !gh pr checks <n> --repo <owner/repo> --watch --fail-fast >/dev/null && gh pr merge ... --admin && ...
# Failing checks and drafts never get --admin. The rofi row says "bypass" or
# "bypass after checks" for those PRs before you pick.
#
# Usage: __pr_merge_pick.sh [erase]   erase = trigger length to backspace
#
# Env: PR_MERGE_REPO (skip repo lookup), PR_MERGE_DIR (directory to resolve the
# repo from instead of the focused tmux pane), PR_MERGE_OPEN=0 (no browser),
# PR_PICK_WATCH_FILE (the pr-watch list to use; empty for none).
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENER="${PR_MERGE_OPENER:-xdg-open}"
LAYOUT_SCRIPT="${PR_MERGE_LAYOUT_SCRIPT:-$SCRIPT_DIR/__layouts.sh}"
LAYOUT="${PR_MERGE_LAYOUT:-18}"
LAYOUT_DELAY="${PR_MERGE_LAYOUT_DELAY:-1.5}"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/__lib_rofi_theme.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/__lib_pr_watch_export.sh"

# One row per open PR: repo, number, author, draft, review, merge state, checks,
# title, joined by the unit separator: a tab is IFS whitespace, so read would
# collapse an empty review field into the next one. checks folds the rollup to
# ok, fail, pending or none. repo is $repo, or read off the PR's URL when the
# PRs come from a pr-watch list and $repo is empty.
# shellcheck disable=SC2016 # jq program, not shell
PR_ROWS_JQ='
def checks:
  [.statusCheckRollup[]?
   | (.conclusion // .state // "") as $c
   | (.status // "COMPLETED") as $s
   | if $s != "COMPLETED" or $c == "" or $c == "PENDING" or $c == "EXPECTED" then "pending"
     elif $c == "SUCCESS" or $c == "NEUTRAL" or $c == "SKIPPED" then "ok"
     else "fail" end]
  | if length == 0 then "none"
    elif any(. == "fail") then "fail"
    elif any(. == "pending") then "pending"
    else "ok" end;
.[] | [(if $repo != "" then $repo else (.url | capture("^https://github\\.com/(?<r>[^/]+/[^/]+)/pull/").r) end),
       .number, .author.login, .isDraft, (.reviewDecision // ""), (.mergeStateStatus // ""), checks,
       (.title | gsub("[\u001f\n]"; " "))] | map(tostring) | join("\u001f")'

notify() {
	command -v notify-send >/dev/null 2>&1 && notify-send "PR merge" "$1"
	return 0
}

# owner/repo of directory $1, via gh's own remote lookup.
resolve_repo() {
	if [[ -n "${PR_MERGE_REPO:-}" ]]; then
		printf '%s\n' "$PR_MERGE_REPO"
		return 0
	fi
	local dir="$1"
	[[ -n "$dir" && -d "$dir" ]] || return 1
	(cd "$dir" && gh repo view --json nameWithOwner) | jq -r '.nameWithOwner // empty'
}

# The open PRs a pr-watch list file names, as one JSON array of gh views in
# the list's order. An entry that is no PR URL is skipped, and so is a PR
# merged or closed since. The views run in parallel: a long session's list
# names a dozen PRs, most of them merged.
watched_prs() {
	local url dir i=0
	dir=$(mktemp -d) || return 1
	while read -r url; do
		[[ "$url" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+$ ]] || continue
		i=$((i + 1))
		gh pr view "$url" --json number,title,url,author,state,isDraft,reviewDecision,mergeStateStatus,statusCheckRollup \
			>"$dir/$(printf '%04d' "$i").json" 2>/dev/null &
	done < <(jq -r '.prs[]?.url // empty' "$1" 2>/dev/null)
	wait
	cat "$dir"/*.json 2>/dev/null | jq -s '[.[] | select(.state == "OPEN")]'
	rm -rf "$dir"
}

# The repo's preferred merge method: squash, then merge commit, then rebase.
merge_method() {
	gh repo view "$1" --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed |
		jq -r 'if .squashMergeAllowed then "squash" elif .mergeCommitAllowed then "merge" else "rebase" end'
}

review_label() {
	case "$1" in
	APPROVED) echo "approved" ;;
	CHANGES_REQUESTED) echo "changes requested" ;;
	REVIEW_REQUIRED) echo "review required" ;;
	*) echo "no review" ;;
	esac
}

# Ctrl+1's sequence: open, give the browser time to map, tile with focus back
# on the terminal (layout 18). Detached so the picker returns at once.
open_pr() {
	[[ "${PR_MERGE_OPEN:-1}" == "0" ]] && return 0
	local url="$1" cmd
	# shellcheck disable=SC2016 # expanded by the inner sh
	cmd='"$1" "$2" >/dev/null 2>&1; sleep "$3"; "$4" "$5" >/dev/null 2>&1'
	if [[ "${PR_MERGE_NO_DETACH:-0}" == "1" ]]; then
		sh -c "$cmd" sh "$OPENER" "$url" "$LAYOUT_DELAY" "$LAYOUT_SCRIPT" "$LAYOUT" </dev/null || true
	else
		setsid -f sh -c "$cmd" sh "$OPENER" "$url" "$LAYOUT_DELAY" "$LAYOUT_SCRIPT" "$LAYOUT" </dev/null >/dev/null 2>&1 || true
	fi
}

pane="" dir="${PR_MERGE_DIR:-}"
if [[ -z "$dir" ]]; then
	read -r pane dir < <(focused_pane) || true
fi

# A worker pane's pr-watch list first; repo stays empty in that mode.
repo="" prs=""
watch_file=$(pr_watch_file "$pane")
if [[ -n "$watch_file" ]]; then
	prs=$(watched_prs "$watch_file" || true)
	[[ "$(jq 'length' <<<"$prs" 2>/dev/null)" =~ ^[1-9] ]] || prs=""
fi
prompt="merge watched PRs"
if [[ -z "$prs" ]]; then
	repo=$(resolve_repo "$dir" || true)
	if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
		notify "No GitHub repo in the focused tmux pane"
		exit 0
	fi
	if ! prs=$(gh pr list --repo "$repo" --state open --limit 100 \
		--json number,title,author,isDraft,reviewDecision,mergeStateStatus,statusCheckRollup); then
		notify "Could not list PRs in $repo"
		exit 0
	fi
	prompt="merge $repo"
fi
mapfile -t rows < <(jq -r --arg repo "$repo" "$PR_ROWS_JQ" <<<"$prs")
if ((${#rows[@]} == 0)); then
	notify "No open PRs in $repo"
	exit 0
fi

# Keyed by the row's ref: #N for the pane's repo, owner/repo#N from a list.
declare -A author draft state checks repo_of num_of

# Whether PR $1 gets --admin: checks green, not a draft, merge blocked anyway.
bypass() {
	[[ "${checks[$1]}" == "ok" && "${state[$1]}" == "BLOCKED" && "${draft[$1]}" != "true" ]]
}

# Whether PR $1 gets --admin once its running checks pass.
bypass_after_checks() {
	[[ "${checks[$1]}" == "pending" && "${state[$1]}" == "BLOCKED" && "${draft[$1]}" != "true" ]]
}
labels=()
for row in "${rows[@]}"; do
	IFS=$'\x1f' read -r o n a d r m c t <<<"$row"
	[[ "$o" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$n" =~ ^[0-9]+$ ]] || continue
	k="#$n"
	[[ -z "$repo" ]] && k="$o#$n"
	author[$k]=$a draft[$k]=$d state[$k]=$m checks[$k]=$c repo_of[$k]=$o num_of[$k]=$n
	flags="checks $c, $(review_label "$r")"
	[[ "$d" == "true" ]] && flags+=", draft"
	bypass "$k" && flags+=", bypass"
	bypass_after_checks "$k" && flags+=", bypass after checks"
	labels+=("$k  $t  [$flags]  @$a")
done

rofi_theme 1400
selection=$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -p "$prompt" "${ROFI_THEME[@]}") || exit 0
k="${selection%% *}"
[[ -n "${author[$k]:-}" ]] || exit 0
pick_repo=${repo_of[$k]} n=${num_of[$k]}

# Erase the trigger only now that rofi has closed, so it never races AutoKey.
erase="${1:-0}"
if [[ "$erase" =~ ^[0-9]+$ ]] && ((erase > 0)); then
	backspaces=()
	for ((i = 0; i < erase; i++)); do backspaces+=(BackSpace); done
	xdotool key --clearmodifiers "${backspaces[@]}"
fi

method=$(merge_method "$pick_repo" || true)
[[ "$method" =~ ^(squash|merge|rebase)$ ]] || method=squash
admin="" wait=""
bypass "$k" && admin=" --admin"
if bypass_after_checks "$k"; then
	admin=" --admin"
	wait="gh pr checks $n --repo $pick_repo --watch --fail-fast >/dev/null && "
fi

xdotool type --clearmodifiers --delay 12 -- \
	"!${wait}gh pr merge $n --repo $pick_repo --$method$admin && __pr_merge_watch.sh $pick_repo $n"
open_pr "https://github.com/$pick_repo/pull/$n"
