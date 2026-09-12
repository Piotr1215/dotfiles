#!/usr/bin/env bash
set -eo pipefail

# Cycle through delegated subagent sessions. The exact mirror of
# __cycle_tmux_session.sh, which skips these on purpose: between them, Alt-PgUp
# and Alt-PgDn walk your own sessions and this key walks the workers, so neither
# ring ever buries the other.
#
# WHY: Alt-m's margin already renders the whole board (__cockpit_state.sh, one
# row per live worker with a "jump:<session>" cell), but that cell is a hint no
# key acts on. With ten workers up, reaching one meant reading its name off the
# margin and hand-driving switch-client. The board had no legs.
#
# Membership is @agent_spawn_level == delegated, the session option
# __spawn_agent.sh:445 stamps at spawn. Not @agent_name, which is a PANE option
# every worker pane carries and which would have made this a pane ring rather
# than a session ring; and not "is claude running here", which would sweep your
# own sessions back in and defeat the split above.
#
# Usage: __cycle_agent_session.sh [next|prev]
# Only next is bound (Alt-i). prev exists because the ring logic is the same
# four lines either way, so a second binding costs nothing later.

direction="${1:-next}"

# Reject anything that is not a direction rather than treating it as prev, which
# is what an "is it next?" test silently does with a typo. Caught by running
# this with a --dry flag it never had: the script read that as prev and switched
# a live client into a worker session. A key binding is not the only caller.
if [[ "$direction" != "next" && "$direction" != "prev" ]]; then
    printf 'usage: %s [next|prev]\n' "${0##*/}" >&2
    exit 2
fi

current=$(tmux display-message -p '#S')

session_spawn_level() {
    tmux show-options -qv -t "$1" @agent_spawn_level 2>/dev/null || true
}

mapfile -t sessions < <(
    tmux list-sessions -F '#S' | while read -r s; do
        [[ "$(session_spawn_level "$s")" == "delegated" ]] && echo "$s"
    done
)

(( ${#sessions[@]} == 0 )) && exit 0

current_idx=-1
for i in "${!sessions[@]}"; do
    [[ "${sessions[$i]}" == "$current" ]] && { current_idx=$i; break; }
done

# Entering the ring from outside it, which is the common case: this key is
# pressed from a working session, not from a worker. Enter at the end the
# direction implies rather than always at the top, so one press of a prev
# binding does not mean "go to the first one".
if (( current_idx == -1 )); then
    if [[ "$direction" == "next" ]]; then
        idx=0
    else
        idx=$(( ${#sessions[@]} - 1 ))
    fi
else
    # Already inside a one-session ring: stepping would switch to where you
    # already are, and tmux would redraw for nothing.
    (( ${#sessions[@]} <= 1 )) && exit 0
    if [[ "$direction" == "next" ]]; then
        idx=$(( (current_idx + 1) % ${#sessions[@]} ))
    else
        idx=$(( (current_idx - 1 + ${#sessions[@]}) % ${#sessions[@]} ))
    fi
fi

target="${sessions[$idx]}"
tmux switch-client -t "$target"

# Land on the pane you can type into. A spawned worker session is two panes, a
# viddy monitor at .1 and the agent at .2, and switch-client restores whichever
# was last active there. Visit a worker, click its monitor to read, cycle away,
# and every later arrival puts the cursor in viddy. The agent pane is the one
# carrying @agent_name, so ask for it by that rather than by index.
agent_pane=$(tmux list-panes -s -t "$target" -F '#{pane_id} #{@agent_name}' 2>/dev/null \
    | awk 'NF > 1 { print $1; exit }')
[[ -n "$agent_pane" ]] && tmux select-window -t "$target:$(tmux display-message -p -t "$agent_pane" '#{window_index}')" 2>/dev/null
[[ -n "$agent_pane" ]] && tmux select-pane -t "$agent_pane" 2>/dev/null

exit 0
