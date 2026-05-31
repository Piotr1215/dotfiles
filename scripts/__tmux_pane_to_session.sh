#!/usr/bin/env bash
set -uo pipefail

# Move the issuing tmux pane into a brand-new session. Safe for any pane,
# including the only pane in its window (where break-pane would fail).
#
# Strategy (all standard tmux primitives, no break-pane):
#   1. resolve the source pane (passed in, or $TMUX_PANE)
#   2. create the new session up front, capturing its placeholder pane
#   3. join-pane the source pane into that session
#   4. kill the placeholder, leaving only the moved pane
#   5. switch the client to follow it
# If the move fails, the freshly-created session is torn down and the source
# pane is left exactly where it was.
#
# Args: $1 = source pane id (defaults to $TMUX_PANE)
#       $2 = explicit session name (optional)
# Name precedence when $2 is empty:
#   pane option @session_name > pane option @agent_name > cwd basename.

pane="${1:-${TMUX_PANE:-}}"
if [[ -z "$pane" ]]; then
  tmux display-message "pane-to-session: no source pane"
  exit 1
fi

name="${2:-}"
[[ -z "$name" ]] && name=$(tmux show-options -pqv -t "$pane" @session_name)
[[ -z "$name" ]] && name=$(tmux show-options -pqv -t "$pane" @agent_name)

# Pane cwd: fallback name source and the new session's root folder.
start=$(tmux display-message -p -t "$pane" '#{pane_current_path}')
[[ -z "$name" ]] && name=$(basename "$start")

# Session names cannot contain '.' or ':'.
name="${name//[.:]/_}"
[[ -z "$name" ]] && name="session"

# Auto-suffix on collision: foo, foo-2, foo-3, ...
base="$name"
n=2
while tmux has-session -t "=$name" 2>/dev/null; do
  name="${base}-${n}"
  n=$((n + 1))
done

# Create the destination session first; capture its placeholder pane id.
placeholder=$(tmux new-session -d -s "$name" -c "$start" -P -F '#{pane_id}')
if [[ -z "$placeholder" ]]; then
  tmux display-message "pane-to-session: could not create session '$name'"
  exit 1
fi

# Move the issuing pane into the new session, then drop the placeholder.
if tmux join-pane -s "$pane" -t "$placeholder"; then
  tmux kill-pane -t "$placeholder"
  tmux switch-client -t "$name" 2>/dev/null || true
else
  tmux kill-session -t "$name"
  tmux display-message "pane-to-session: move failed, source pane left in place"
  exit 1
fi
