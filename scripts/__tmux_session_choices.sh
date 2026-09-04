#!/usr/bin/env bash
# Render active tmux sessions with delegated workers nested under their parent.
# Nothing is filtered. `resolve` strips the chrome back to a real session name.
set -euo pipefail

marker=' ◀◀◀'
dormant=' ○'

resolve_choice() {
    local choice="$1"
    if [[ "$choice" == *"$marker" ]]; then
        choice="${choice%"$marker"}"
    elif [[ "$choice" == *"$dormant" ]]; then
        choice="${choice%"$dormant"}"
    else
        return 1
    fi
    choice="${choice#"${choice%%[![:space:]]*}"}"
    if [[ "$choice" == "- "* ]]; then
        choice="${choice#- }"
    elif [[ "$choice" == "↳ "* ]]; then
        choice="${choice#↳ }"
        choice="${choice%% ← *}"
    fi
    [[ "$choice" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    printf '%s\n' "$choice"
}

list_choices() {
    local session paneinfo agent level parent node depth
    declare -a sessions=()
    declare -A session_by_agent=() parent_by_session=() depth_by_session=() root_by_session=()

    mapfile -t sessions < <(tmux list-sessions -F '#{session_name}' 2>/dev/null | sort -u)
    for session in "${sessions[@]}"; do
        paneinfo=$(tmux list-panes -t "$session" -F '#{pane_active}|#{@agent_name}' 2>/dev/null \
            | awk -F'|' '$1==1{print $2; exit}')
        agent="${paneinfo:-$session}"
        session_by_agent["$agent"]="$session"
    done

    for session in "${sessions[@]}"; do
        level=$(tmux show-options -qv -t "$session" @agent_spawn_level 2>/dev/null || true)
        parent=$(tmux show-options -qv -t "$session" @agent_spawn_parent 2>/dev/null || true)
        if [[ "$level" == delegated && -n "$parent" ]]; then
            parent_by_session["$session"]="${session_by_agent[$parent]:-$parent}"
        fi
    done

    for session in "${sessions[@]}"; do
        node="$session"; depth=0
        declare -A seen=()
        while [[ -n "${parent_by_session[$node]:-}" && -z "${seen[$node]:-}" ]]; do
            seen["$node"]=1
            node="${parent_by_session[$node]}"
            depth=$((depth + 1))
            (( depth < 12 )) || break
        done
        root_by_session["$session"]="$node"
        depth_by_session["$session"]="$depth"
    done

    for session in "${sessions[@]}"; do
        printf '%s\t%02d\t%s\n' \
            "${root_by_session[$session]}" "${depth_by_session[$session]}" "$session"
    done | sort -t$'\t' -k1,1 -k2,2n -k3,3 | while IFS=$'\t' read -r _root depth session; do
        if (( depth > 0 )); then
            printf '  - %s%s\n' "$session" "$marker"
        else
            printf '%s%s\n' "$session" "$marker"
        fi
    done
}

# Tmuxinator configs with no running session. Marked so the picker reads them as
# sessions rather than bare words sitting among absolute paths.
list_dormant() {
    local active session
    active=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | sort -u)
    while IFS= read -r session; do
        [[ -n "$session" ]] || continue
        grep -qxF "$session" <<<"$active" && continue
        printf '%s%s\n' "$session" "$dormant"
    done < <(ls --color=never ~/.config/tmuxinator/*.yml 2>/dev/null \
        | xargs -n1 basename 2>/dev/null | sed 's/\.yml$//' | sort)
}

case "${1:-list}" in
    list)
        list_choices
        ;;
    dormant)
        list_dormant
        ;;
    resolve)
        resolve_choice "${2:-}"
        ;;
    *)
        echo "usage: ${0##*/} list|dormant|resolve <choice>" >&2
        exit 2
        ;;
esac
