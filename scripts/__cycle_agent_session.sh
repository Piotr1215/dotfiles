#!/usr/bin/env bash
set -eo pipefail

# Cycle through every live agent pane in the order the Alt-m cockpit lists them.
#
# WHY: this key used to walk only delegated sessions, in tmux's own session
# order, so it jumped around while the cockpit showed another order entirely.
# The order now comes from __cockpit_state.sh itself (COCKPIT_LAYOUT=order, the
# sorted rows the board renders), so the ring cannot drift from the list. Gordon
# and intake share the `task` session in different windows, so the ring steps
# by pane, not by session.
#
# Next is the entry after the one holding the current pane, wrapping at the end.
# From a pane that is not an agent, next enters at the first entry and prev at
# the last.
#
# Usage: __cycle_agent_session.sh [next|prev] [current-pane-id]
# Only next is bound (Alt-i).

direction="${1:-next}"

# Reject anything that is not a direction rather than treating it as prev, which
# is what an "is it next?" test silently does with a typo. A key binding is not
# the only caller.
if [[ "$direction" != "next" && "$direction" != "prev" ]]; then
    printf 'usage: %s [next|prev]\n' "${0##*/}" >&2
    exit 2
fi

state="${COCKPIT_STATE:-$HOME/.claude/scripts/__cockpit_state.sh}"
cache_dir="${CYCLE_AGENT_CACHE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/cycle-agent-order}"
cache="$cache_dir/order"
ttl="${CYCLE_AGENT_TTL:-8}"
mkdir -p "$cache_dir"

# The cockpit render takes seconds, far too slow for a key press. Read the last
# render from a cache and refresh it in the background when it is older than the
# ttl. Presses inside the ttl all see one frozen order, so the ring does not
# reshuffle while you step through it. Only a cold cache renders inline.
refresh_cache() {
    (
        flock -n 9 || exit 0
        COCKPIT_LAYOUT=order "$state" > "$cache.$$" 2>/dev/null \
            && [ -s "$cache.$$" ] && mv -f "$cache.$$" "$cache"
        rm -f "$cache.$$"
    ) 9>"$cache_dir/lock"
}

if [[ ! -s "$cache" ]]; then
    refresh_cache
elif [[ -z "$(find "$cache" -mmin -"$(awk -v t="$ttl" 'BEGIN{printf "%.4f", t/60}')" 2>/dev/null)" ]]; then
    refresh_cache </dev/null >/dev/null 2>&1 &
    disown
fi

# The pane the client is on arrives from the binding (#{pane_id} is expanded by
# run-shell); fall back to asking tmux when run by hand.
current="${2:-$(tmux display-message -p '#{pane_id}')}"

[[ -r "$cache" ]] || exit 0

# Drop panes that died since the render, so a stale cache never targets a ghost.
mapfile -t live < <(tmux list-panes -a -F '#{pane_id}')
panes=()
while IFS= read -r p; do
    for l in "${live[@]}"; do [[ "$l" == "$p" ]] && { panes+=("$p"); break; }; done
done < "$cache"

(( ${#panes[@]} == 0 )) && exit 0

current_idx=-1
for i in "${!panes[@]}"; do
    [[ "${panes[$i]}" == "$current" ]] && { current_idx=$i; break; }
done

if (( current_idx == -1 )); then
    if [[ "$direction" == "next" ]]; then
        idx=0
    else
        idx=$(( ${#panes[@]} - 1 ))
    fi
else
    # A one-entry ring that already holds the current pane has nowhere to go.
    (( ${#panes[@]} <= 1 )) && exit 0
    if [[ "$direction" == "next" ]]; then
        idx=$(( (current_idx + 1) % ${#panes[@]} ))
    else
        idx=$(( (current_idx - 1 + ${#panes[@]}) % ${#panes[@]} ))
    fi
fi

target="${panes[$idx]}"

# switch-client picks the session; the window and pane are selected by id so a
# shared session (task) lands on the right agent, not on whatever was active.
tmux switch-client -t "$target"
tmux select-window -t "$target" 2>/dev/null || true
tmux select-pane -t "$target" 2>/dev/null || true

exit 0
