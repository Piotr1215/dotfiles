#!/usr/bin/env bash
# PROJECT: pr-merge
# ;;merge picker. Lists the open PRs of the repo in the focused tmux pane in
# rofi, types a merge command for the pick, and opens the PR in the browser
# tiled beside the terminal, the way the ctrl+1 alacritty hint does.
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
# repo from instead of the focused tmux pane), PR_MERGE_OPEN=0 (no browser).
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENER="${PR_MERGE_OPENER:-xdg-open}"
LAYOUT_SCRIPT="${PR_MERGE_LAYOUT_SCRIPT:-$SCRIPT_DIR/__layouts.sh}"
LAYOUT="${PR_MERGE_LAYOUT:-18}"
LAYOUT_DELAY="${PR_MERGE_LAYOUT_DELAY:-1.5}"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/__lib_rofi_theme.sh"

# One row per open PR: number, author, draft, review, merge state, checks, title,
# joined by the unit separator: a tab is IFS whitespace, so read would collapse
# an empty review field into the next one. checks folds the rollup to ok, fail,
# pending or none.
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
.[] | [.number, .author.login, .isDraft, (.reviewDecision // ""), (.mergeStateStatus // ""), checks,
       (.title | gsub("[\u001f\n]"; " "))] | map(tostring) | join("\u001f")'

notify() {
	command -v notify-send >/dev/null 2>&1 && notify-send "PR merge" "$1"
	return 0
}

# Directory of the pane you are looking at: the active pane of the session the
# most recently used tmux client shows. AutoKey runs outside tmux, and a bare
# `tmux display-message` there resolves the session with the newest activity,
# which is whichever agent printed last, not the one on screen.
focused_dir() {
	tmux list-clients -F '#{client_activity} #{pane_current_path}' 2>/dev/null |
		sort -rn | head -n1 | cut -d' ' -f2-
}

# owner/repo of the focused pane's directory, via gh's own remote lookup.
resolve_repo() {
	if [[ -n "${PR_MERGE_REPO:-}" ]]; then
		printf '%s\n' "$PR_MERGE_REPO"
		return 0
	fi
	local dir="${PR_MERGE_DIR:-}"
	[[ -z "$dir" ]] && dir=$(focused_dir)
	[[ -n "$dir" && -d "$dir" ]] || return 1
	(cd "$dir" && gh repo view --json nameWithOwner) | jq -r '.nameWithOwner // empty'
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

repo=$(resolve_repo || true)
if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
	notify "No GitHub repo in the focused tmux pane"
	exit 0
fi

if ! prs=$(gh pr list --repo "$repo" --state open --limit 100 \
	--json number,title,author,isDraft,reviewDecision,mergeStateStatus,statusCheckRollup); then
	notify "Could not list PRs in $repo"
	exit 0
fi
mapfile -t rows < <(jq -r "$PR_ROWS_JQ" <<<"$prs")
if ((${#rows[@]} == 0)); then
	notify "No open PRs in $repo"
	exit 0
fi

declare -A author draft state checks

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
	IFS=$'\x1f' read -r n a d r m c t <<<"$row"
	author[$n]=$a draft[$n]=$d state[$n]=$m checks[$n]=$c
	flags="checks $c, $(review_label "$r")"
	[[ "$d" == "true" ]] && flags+=", draft"
	bypass "$n" && flags+=", bypass"
	bypass_after_checks "$n" && flags+=", bypass after checks"
	labels+=("#$n  $t  [$flags]  @$a")
done

rofi_theme 1400
selection=$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -p "merge $repo" "${ROFI_THEME[@]}") || exit 0
n="${selection#\#}"
n="${n%% *}"
[[ "$n" =~ ^[0-9]+$ && -n "${author[$n]:-}" ]] || exit 0

# Erase the trigger only now that rofi has closed, so it never races AutoKey.
erase="${1:-0}"
if [[ "$erase" =~ ^[0-9]+$ ]] && ((erase > 0)); then
	backspaces=()
	for ((i = 0; i < erase; i++)); do backspaces+=(BackSpace); done
	xdotool key --clearmodifiers "${backspaces[@]}"
fi

method=$(merge_method "$repo" || true)
[[ "$method" =~ ^(squash|merge|rebase)$ ]] || method=squash
admin="" wait=""
bypass "$n" && admin=" --admin"
if bypass_after_checks "$n"; then
	admin=" --admin"
	wait="gh pr checks $n --repo $repo --watch --fail-fast >/dev/null && "
fi

xdotool type --clearmodifiers --delay 12 -- \
	"!${wait}gh pr merge $n --repo $repo --$method$admin && __pr_merge_watch.sh $repo $n"
open_pr "https://github.com/$repo/pull/$n"
