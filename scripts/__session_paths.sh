#!/usr/bin/env bash
# Session files of the Claude Code and Codex sessions in the focused window,
# one "PATH | label" line each: the ;;session value-set. Prints nothing when
# that window runs neither, so the trigger stays as typed. With --here, the
# session this command runs under instead, as from a ! command in Claude Code.
#
# The focused window's process tree is searched; when a tmux client runs in
# it, the pane that client shows is searched instead, so a session in another
# pane never matches. Claude Code records each process in
# <home>/sessions/<pid>.json with its session id. Codex holds a session's
# rollout file open in its app-server daemon, which is detached and shared,
# so a Codex pane is matched by its working directory against the cwd on the
# first line of each rollout some codex process holds open.
set -eo pipefail

PROC_ROOT="${PROC_ROOT:-/proc}"
read -r -a CLAUDE_HOMES <<< "${CLAUDE_HOMES:-$HOME/.claude $HOME/.claude-work}"

# Every process as "pid ppid comm", read once.
procs=$(ps -e -o pid=,ppid=,comm=)

# Print PID and all its descendants, one per line.
subtree() {
	awk -v root="$1" '{ kids[$2] = kids[$2] " " $1 }
		END {
			q[1] = root; n = 1
			for (i = 1; i <= n; i++) {
				print q[i]
				c = split(kids[q[i]], k, " ")
				for (j = 1; j <= c; j++) q[++n] = k[j]
			}
		}' <<< "$procs"
}

# Print the processes on screen: the focused window's tree, or the trees of
# the panes shown by the tmux clients running in it.
on_screen() {
	local win wpid tree panes p
	win=$(xdotool getactivewindow 2>/dev/null) || return 0
	wpid=$(xdotool getwindowpid "$win" 2>/dev/null) || return 0
	[[ -n "$wpid" ]] || return 0
	tree=$(subtree "$wpid")
	# No tmux server is no clients, not a failure.
	panes=$(tmux list-clients -F '#{client_pid} #{pane_pid}' 2>/dev/null |
		awk 'NR == FNR { shown[$1]; next } $1 in shown { print $2 }' <(printf '%s\n' "$tree") -) || true
	if [[ -z "$panes" ]]; then
		printf '%s\n' "$tree"
		return 0
	fi
	while read -r p; do subtree "$p"; done <<< "$panes"
}

# Print PID and the processes it runs under, up to init.
ancestors() {
	awk -v p="$1" '{ parent[$1] = $2 }
		END { while (p > 1 && !(p in seen)) { print p; seen[p]; p = parent[p] } }' <<< "$procs"
}

# Print the command name of PID.
comm_of() {
	awk -v p="$1" '$1 == p { print $3; exit }' <<< "$procs"
}

# Print the transcript of the interactive Claude Code session PID runs.
claude_session() {
	local home record sid path
	for home in "${CLAUDE_HOMES[@]}"; do
		record="$home/sessions/$1.json"
		[[ -f "$record" ]] || continue
		sid=$(jq -r 'select(.kind == "interactive") | .sessionId // empty' "$record")
		[[ -n "$sid" ]] || continue
		for path in "$home"/projects/*/"$sid.jsonl"; do
			if [[ -f "$path" ]]; then
				printf '%s | claude %s\n' "$path" "$(jq -r '.name // ""' "$record")"
			fi
		done
	done
}

# Print the rollout files some codex process holds open: the live sessions.
open_rollouts() {
	local p fd
	awk '$3 == "codex" { print $1 }' <<< "$procs" | while read -r p; do
		for fd in "$PROC_ROOT/$p"/fd/*; do readlink "$fd" 2>/dev/null || true; done
	done | grep -E '/sessions/.+/rollout-[^/]+\.jsonl$' | sort -u || true
}

# Print the live Codex sessions started in the directory PID runs in.
codex_sessions() {
	local cwd rollout
	cwd=$(readlink "$PROC_ROOT/$1/cwd" 2>/dev/null) || return 0
	while read -r rollout; do
		[[ -n "$rollout" ]] || continue
		if [[ "$(head -1 "$rollout" | jq -r '.payload.cwd // empty' 2>/dev/null)" == "$cwd" ]]; then
			printf '%s | codex %s\n' "$rollout" "$cwd"
		fi
	done <<< "$rollouts"
}

rollouts=$(open_rollouts)
if [[ "${1:-}" == --here ]]; then
	pids=$(ancestors "${SESSION_FROM_PID:-$$}")
else
	pids=$(on_screen | sort -u)
fi
[[ -n "$pids" ]] || exit 0
while read -r pid; do
	case "$(comm_of "$pid")" in
	claude) claude_session "$pid" ;;
	codex) codex_sessions "$pid" ;;
	esac
done <<< "$pids" | sort -u
