#!/usr/bin/env bash
set -eo pipefail

# Cycle through tmux sessions, excluding relax, poke, and music sessions
# Note: If the current session is one of these, do NOT exclude it
# Note: poke is only skipped while idle (a single pane). Once it holds real
#       work (extra panes or windows) it cycles like any other session.
# Usage: __cycle_tmux_session.sh [next|prev]

direction="${1:-next}"

current=$(tmux display-message -p '#S')

# Total panes across every window of a session
session_pane_count() {
    tmux list-panes -s -t "$1" -F '#{pane_id}' 2>/dev/null | wc -l
}

# Get music session if playing
music_session=""
[[ -f "/tmp/current_music_session.txt" ]] && music_session=$(cat "/tmp/current_music_session.txt" 2>/dev/null || true)

# Get filtered sessions
mapfile -t sessions < <(
    tmux list-sessions -F '#S' | while read -r s; do
        # Exclude relax/poke/music unless it's the current session
        if [[ "$s" != "$current" ]]; then
            [[ "$s" == "relax" ]] && continue
            [[ "$s" == "poke" && "$(session_pane_count "$s")" -le 1 ]] && continue
            [[ -n "$music_session" && "$s" == "$music_session" ]] && continue
        fi
        echo "$s"
    done
)

(( ${#sessions[@]} <= 1 )) && exit 0

# Find current index
current_idx=-1
for i in "${!sessions[@]}"; do
    [[ "${sessions[$i]}" == "$current" ]] && { current_idx=$i; break; }
done

# If current not in list, go to first
(( current_idx == -1 )) && { tmux switch-client -t "${sessions[0]}"; exit 0; }

# Calculate target index
if [[ "$direction" == "next" ]]; then
    idx=$(( (current_idx + 1) % ${#sessions[@]} ))
else
    idx=$(( (current_idx - 1 + ${#sessions[@]}) % ${#sessions[@]} ))
fi

tmux switch-client -t "${sessions[$idx]}"
