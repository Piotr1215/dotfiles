#!/usr/bin/env bash
# PROJECT: pr-merge
# Shared by the ;;merge and ;;spacelift pickers: the pane on screen, and the
# pr-watch list of the Claude session in it. __spawn_agent.sh starts every
# Claude worker in pr-watch scope all with PR_WATCH_EXPORT, a file its pr-watch
# rewrites with the PRs it watches, from any repo, and records that path on the
# pane as @pr_watch_export. A pane without it (your own sessions, Codex
# workers) has no list, and the pickers do what they did before.
#
# Env: PR_PICK_WATCH_FILE names the list file outright (empty: none).

# "<pane id> <directory>" of the active pane in the session the most recently
# used tmux client shows. AutoKey runs outside tmux, and a bare
# `tmux display-message` there resolves the session with the newest activity,
# which is whichever agent printed last, not the one on screen.
focused_pane() {
	tmux list-clients -F '#{client_activity} #{pane_id} #{pane_current_path}' 2>/dev/null |
		sort -rn | head -n1 | cut -d' ' -f2-
}

# The readable pr-watch list file of pane $1, or nothing.
pr_watch_file() {
	local file=""
	if [[ -n "${PR_PICK_WATCH_FILE+x}" ]]; then
		file="$PR_PICK_WATCH_FILE"
	elif [[ -n "${1:-}" ]]; then
		file=$(tmux show-options -pqv -t "$1" @pr_watch_export 2>/dev/null || true)
	fi
	[[ -n "$file" && -r "$file" ]] && printf '%s\n' "$file"
	return 0
}
