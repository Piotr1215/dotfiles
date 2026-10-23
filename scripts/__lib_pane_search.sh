#!/usr/bin/env bash
# Library for the M-x pane text search (__file_opener.sh, Ctrl-S).
# Builds the fzf index: one row per pane line, tab-delimited as
#   pane_id <TAB> label <TAB> line-text
# Two modes:
#   agents (default)  agent panes only, cockpit order, one row per distinct line
#                     per pane (most recent kept), labelled with the agent name
#   all               every pane, every line, labelled session:win.pane
# Run directly it calls a function: bash __lib_pane_search.sh pane_search_index all
#
# Overrides for tests: PANE_SEARCH_ORDER_CMD (prints pane ids, cockpit order),
# PANE_SEARCH_SCROLLBACK (capture depth, default 3000).

# Cockpit order source: one pane id per live agent row, in board order.
pane_search_agent_order_live() {
    if [[ -n "${PANE_SEARCH_ORDER_CMD:-}" ]]; then
        eval "$PANE_SEARCH_ORDER_CMD"
    else
        COCKPIT_LAYOUT=order bash "$HOME/.claude/scripts/__cockpit_state.sh" 2>/dev/null
    fi
}

# Rendering the board takes seconds, so the picker reads a cached order
# (PANE_SEARCH_ORDER_CACHE) and refreshes it in the background. Fresh (under
# 60s) or stale (under 1h) cache is used as is; stale also triggers a refresh.
# No usable cache: compute synchronously. A pane the cache does not know yet is
# missing from the agents view until the refresh lands; the all view has it.
pane_search_agent_order() {
    local cache="${PANE_SEARCH_ORDER_CACHE:-/tmp/pane_search_order_${USER:-u}}" age=-1
    [[ -s "$cache" ]] && age=$(($(date +%s) - $(stat -c %Y "$cache")))
    if (( age >= 0 && age < 3600 )); then
        if (( age >= 60 )); then
            ( pane_search_agent_order_live >"$cache.$$" 2>/dev/null \
                && [[ -s "$cache.$$" ]] && mv "$cache.$$" "$cache"; rm -f "$cache.$$" ) \
                >/dev/null 2>&1 &
            disown 2>/dev/null
        fi
        cat "$cache"
        return
    fi
    pane_search_agent_order_live | tee "$cache.$$"
    [[ -s "$cache.$$" ]] && mv "$cache.$$" "$cache"
    rm -f "$cache.$$"
}

# Agent label for a pane, same naming rule as the cockpit board: @agent_name,
# else the session name. The triage agent in session task is shown as gordon;
# a triage tag anywhere else falls back to the session name.
# Args: session agent_name
pane_search_label() {
    local sess="$1" aname="$2" name
    name="${aname:-$sess}"
    if [[ "$name" == triage ]]; then
        if [[ "$sess" == task ]]; then name=gordon; else name="$sess"; fi
    fi
    printf '%s' "$name"
}

# Capture one pane to stdout: tabs flattened, blank lines dropped.
_pane_search_capture() {
    tmux capture-pane -p -S "-${PANE_SEARCH_SCROLLBACK:-3000}" -t "$1" 2>/dev/null \
        | tr '\t' ' ' | command grep -vE '^[[:space:]]*$'
}

# Keep the last occurrence of each line (whitespace-trimmed for comparison),
# preserving order. Input is oldest to newest, so the newest copy survives.
_pane_search_dedupe() {
    tac | awk '{ k=$0; gsub(/^[ \t]+|[ \t]+$/, "", k); if (!(k in s)) { s[k]=1; print } }' | tac
}

# Print the index for mode "agents" or "all".
pane_search_index() {
    local mode="${1:-agents}" tmp pid sess win pidx aname loc
    tmp=$(mktemp -d) || return 1
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    declare -A loc_of label_of
    local -a all_ids=() ids=() jobs_pids=()
    while IFS='|' read -r pid sess win pidx aname; do
        [[ -n "$pid" ]] || continue
        all_ids+=("$pid")
        loc_of[$pid]="$sess:$win.$pidx"
        label_of[$pid]="$(pane_search_label "$sess" "$aname")"
    done < <(tmux list-panes -a -F '#{pane_id}|#{session_name}|#{window_index}|#{pane_index}|#{@agent_name}' 2>/dev/null)

    # The order lookup is slow (it renders the whole board), so run it beside
    # the captures instead of before them.
    if [[ "$mode" == all ]]; then
        ids=("${all_ids[@]}")
    else
        pane_search_agent_order >"$tmp/order" &
        jobs_pids+=($!)
    fi
    for pid in "${all_ids[@]}"; do
        _pane_search_capture "$pid" >"$tmp/cap.${pid#%}" &
        jobs_pids+=($!)
    done
    wait "${jobs_pids[@]}"

    if [[ "$mode" != all ]]; then
        local seen=" "
        while IFS= read -r pid; do
            [[ -n "${loc_of[$pid]:-}" && "$seen" != *" $pid "* ]] || continue
            seen+="$pid "
            ids+=("$pid")
        done <"$tmp/order"
    fi

    for pid in "${ids[@]}"; do
        if [[ "$mode" == all ]]; then
            loc="${loc_of[$pid]}"
            awk -v p="$pid" -v l="$loc" '{ printf "%s\t%s\t%s\n", p, l, $0 }' "$tmp/cap.${pid#%}"
        else
            loc="${label_of[$pid]}"
            _pane_search_dedupe <"$tmp/cap.${pid#%}" \
                | awk -v p="$pid" -v l="$loc" '{ printf "%s\t%s\t%s\n", p, l, $0 }'
        fi
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    "$@"
fi
