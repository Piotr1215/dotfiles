#!/usr/bin/env bash
# PROJECT: pr-merge
# Follows the workflow runs a merged PR started. Opens a floating tmux pane
# running viddy over `gh run list` for the PR's merge commit; q closes it.
# The ;;merge picker (__pr_merge_pick.sh) chains this after `gh pr merge`.
#
# Usage: __pr_merge_watch.sh <owner/repo> <pr-number>
set -eo pipefail

repo="${1:-}"
pr="${2:-}"
if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ || ! "$pr" =~ ^[0-9]+$ ]]; then
	echo "Usage: __pr_merge_watch.sh <owner/repo> <pr-number>" >&2
	exit 1
fi

sha=$(gh pr view "$pr" --repo "$repo" --json mergeCommit | jq -r '.mergeCommit.oid // empty')
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
	echo "$repo#$pr has no merge commit yet" >&2
	exit 1
fi

runs="gh run list --repo $repo --commit $sha"
# Outside tmux there is nowhere to float a pane: print the runs once instead.
if [[ -z "${TMUX:-}" ]]; then
	$runs
	exit 0
fi
tmux new-pane -d -x 45% -y 80% -X 53% -Y 2 ${TMUX_PANE:+-t "$TMUX_PANE"} "viddy -n 10s -t '$runs'"
echo "Watching runs for $repo#$pr (${sha:0:7}) in a floating pane; q closes it."
