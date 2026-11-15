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
# A cwd-basename session is renamed in the background once Haiku names it from
# the pane's cwd, branch and running command (Piotr, 15 Nov). The move itself
# never waits on Haiku; a failed or taken name keeps the basename.

NAMER="${TMUX_SESSION_NAMER:-$HOME/.claude/scripts/__spawn_session_name.py}"

# haiku_rename PANE SESSION_ID OLD_NAME CWD: ask the namer for a name on the
# account the cwd belongs to (~/loft is work) and rename the session to it.
haiku_rename() {
  local pane="$1" sid="$2" old="$3" cwd="$4" where=home branch cmd new
  [[ -x "$NAMER" ]] || return 0
  [[ "$cwd" == "$HOME/loft" || "$cwd" == "$HOME/loft/"* ]] && where=work
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  cmd=$(tmux display-message -p -t "$pane" '#{pane_current_command}')
  new=$(printf 'Terminal work in the project "%s" (folder %s), git branch %s, running %s. Name the session after the project and branch.\n' \
    "$(basename "$cwd")" "${cwd/#$HOME/\~}" "${branch:-none}" "$cmd" | timeout 15 "$NAMER" --where "$where") || return 0
  [[ "$new" =~ ^[a-z0-9][a-z0-9-]{1,59}$ ]] || return 0
  tmux has-session -t "=$new" 2>/dev/null && return 0
  tmux rename-session -t "$sid" "$new" && tmux display-message "session '$old' renamed '$new'"
}

# --rename: the detached second half started below, after the move.
if [[ "${1:-}" == --rename ]]; then
  shift
  haiku_rename "$@"
  exit 0
fi

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
auto_name=0
[[ -z "$name" ]] && { name=$(basename "$start"); auto_name=1; }

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
# Leave the new session detached; don't follow it. Just report it in the
# status bar of whichever client stays active.
sid=$(tmux display-message -p -t "$placeholder" '#{session_id}')
if tmux join-pane -s "$pane" -t "$placeholder"; then
  tmux kill-pane -t "$placeholder"
  tmux display-message "session '$name' created from current pane (detached)"
  # setsid and closed fds: the caller (tmux run-shell) must not wait on Haiku.
  [[ $auto_name -eq 1 && -x "$NAMER" ]] && setsid -f "$0" --rename "$pane" "$sid" "$name" "$start" </dev/null >/dev/null 2>&1 3>&-
  exit 0
else
  tmux kill-session -t "$name"
  tmux display-message "pane-to-session: move failed, source pane left in place"
  exit 1
fi
