#!/usr/bin/env bash
# Display active/started taskwarrior task, approved PRs, and time for tmux status bar
# Two modes: default (fast reader for status bar) and --update (async writer)
set -eo pipefail

CACHE_DIR="/tmp/tmux_task_status"
mkdir -p "$CACHE_DIR"

# Fast path: status bar just reads pre-computed file + fresh time
if [ "${1:-}" != "--update" ]; then
    session=$(tmux display-message -p '#S' 2>/dev/null || echo "default")
    cache_file="$CACHE_DIR/${session}"
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
    else
        echo "$(date +"%H:%M")"
    fi
    exit 0
fi

# --- Async update mode (called by tmux hooks in background) ---

is_time_off() {
    local current_day=$(date +"%A")
    if [[ "$current_day" == "Saturday" ]] || [[ "$current_day" == "Sunday" ]]; then
        return 0
    fi

    if [ -f "/tmp/timeoff_mode" ]; then
        return 0
    fi

    local boot_script="/home/decoder/dev/dotfiles/scripts/__boot.sh"
    if [ -f "$boot_script" ]; then
        local timeoff=$(grep -E '^timeoff=' "$boot_script" | cut -d'=' -f2)
        if [ "$timeoff" = "1" ]; then
            return 0
        fi
    fi
    return 1
}

truncate_desc() {
    local desc="$1" max="${2:-50}"
    if [ ${#desc} -gt "$max" ]; then
        echo "${desc:0:$((max - 3))}..."
    else
        echo "$desc"
    fi
}

get_session_linear_id() {
    local session
    session=$(tmux display-message -p '#S' 2>/dev/null) || return
    if [[ "$session" =~ ([a-z]+-[0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'
    fi
}

lookup_linear_desc() {
    local linear_id="$1"
    task rc.verbose=nothing "linear_issue_id:$linear_id" export 2>/dev/null | jq -r '.[0].description // empty' 2>/dev/null
}

get_agent_issue() {
    command -v task &> /dev/null || return
    local session_lid
    session_lid=$(get_session_linear_id)
    [ -z "$session_lid" ] && return
    local desc
    desc=$(lookup_linear_desc "$session_lid")
    [ -n "$desc" ] && echo "$desc"
}

get_task_status() {
    command -v task &> /dev/null || return

    local active_task
    active_task=$(task rc.verbose=nothing status:pending start.any: export 2>/dev/null | jq -r 'sort_by(.start) | reverse | .[0]' 2>/dev/null)
    if [ -n "$active_task" ] && [ "$active_task" != "null" ]; then
        local linear_id desc
        linear_id=$(echo "$active_task" | jq -r '.linear_issue_id // empty')
        desc=$(echo "$active_task" | jq -r '.description // empty')
        if [ -n "$desc" ]; then
            desc=$(truncate_desc "$desc")
            [ -n "$linear_id" ] && echo "CUR: $desc ($linear_id)" || echo "CUR: $desc"
            return
        elif [ -n "$linear_id" ]; then
            echo "CUR: $linear_id"; return
        fi
    fi

    local last_completed
    last_completed=$(task rc.verbose=nothing status:completed linear_issue_id.any: export 2>/dev/null | jq -r 'sort_by(.end) | reverse | .[0]' 2>/dev/null)
    if [ -n "$last_completed" ] && [ "$last_completed" != "null" ]; then
        local linear_id desc
        linear_id=$(echo "$last_completed" | jq -r '.linear_issue_id // empty')
        desc=$(echo "$last_completed" | jq -r '.description // empty')
        if [ -n "$desc" ]; then
            desc=$(truncate_desc "$desc")
            [ -n "$linear_id" ] && echo "LAST: $desc ($linear_id)" || echo "LAST: $desc"
            return
        elif [ -n "$linear_id" ]; then
            echo "LAST: $linear_id"; return
        fi
    fi
}

get_approved_prs() {
    if ! command -v task &> /dev/null; then
        echo ""
        return
    fi

    local approved_count=$(task rc.verbose=nothing +pr_approved status:pending count 2>/dev/null)

    if [ -n "$approved_count" ] && [ "$approved_count" -gt 0 ]; then
        local state_file="/tmp/tmux_pr_count_${USER}"
        local prev_count=0
        local indicator=""

        if [ -f "$state_file" ]; then
            prev_count=$(cat "$state_file" 2>/dev/null || echo 0)
        fi

        echo "$approved_count" > "$state_file"

        local animation_file="/tmp/tmux_pr_animation_${USER}"
        local direction_file="/tmp/tmux_pr_direction_${USER}"

        if [ "$approved_count" -gt "$prev_count" ]; then
            echo "$(date +%s)" > "$animation_file"
            echo "up" > "$direction_file"
            indicator=" ↑"
        elif [ "$approved_count" -lt "$prev_count" ]; then
            echo "$(date +%s)" > "$animation_file"
            echo "down" > "$direction_file"
            indicator=" ↓"
        else
            if [ -f "$animation_file" ]; then
                local animation_time=$(cat "$animation_file" 2>/dev/null || echo 0)
                local current_time=$(date +%s)
                local time_diff=$((current_time - animation_time))

                if [ "$time_diff" -lt 5 ]; then
                    if [ -f "$direction_file" ]; then
                        local direction=$(cat "$direction_file")
                        if [ "$direction" = "up" ]; then
                            indicator=" ↑"
                        elif [ "$direction" = "down" ]; then
                            indicator=" ↓"
                        fi
                    fi
                else
                    rm -f "$animation_file" "$direction_file"
                fi
            fi
        fi

        echo "PR ✅ ${approved_count}${indicator}"
        return
    fi
    echo ""
}

get_mpv_status() {
    pgrep -x mpv > /dev/null || return

    local socket_dir="${HOME}/.mpv_sockets"
    local title=""

    if [ -d "$socket_dir" ]; then
        for socket in "$socket_dir"/*; do
            [ -S "$socket" ] || continue
            title=$(echo '{"command": ["get_property", "media-title"]}' | socat - "$socket" 2>/dev/null | jq -r '.data // empty' 2>/dev/null)
            [ -z "$title" ] && title=$(echo '{"command": ["get_property", "filename"]}' | socat - "$socket" 2>/dev/null | jq -r '.data // empty' 2>/dev/null)
            [ -n "$title" ] && break
        done
    fi

    [ -z "$title" ] && title=$(pgrep -a mpv | head -1 | sed 's/.*mpv //' | sed 's/^.*\///' | cut -c1-30)

    if [ -n "$title" ]; then
        echo "🎵 $(truncate_desc "$title" 25)"
    else
        echo "🎵 Playing"
    fi
}

# Update all session cache files
update_session() {
    local session="$1"
    local current_time=$(date +"%H:%M")
    local output=""

    # Temporarily override for per-session linear ID lookup
    local orig_session_fn=$(declare -f get_session_linear_id)
    get_session_linear_id() {
        if [[ "$session" =~ ([a-zA-Z]+-[0-9]+)$ ]]; then
            echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'
        fi
    }

    agent_info=$(get_agent_issue)
    if [ -n "$agent_info" ]; then
        output="📋 $agent_info"
    else
        mpv_status=$(get_mpv_status)
        if [ -n "$mpv_status" ]; then
            output="$mpv_status"
        else
            task_info=$(get_task_status)
            [ -n "$task_info" ] && output="📋 $task_info"
        fi
    fi

    if is_time_off; then
        output="${output:+$output | }$(date +"%a") W$(date +"%V")"
    else
        approved_prs=$(get_approved_prs)
        [ -n "$approved_prs" ] && output="${output:+$output | }$approved_prs"
    fi

    echo "${output:+$output | }$current_time" > "$CACHE_DIR/${session}"

    # Restore original function
    eval "$orig_session_fn"
}

# Prevent pile-up: skip if another update is already running
LOCK_FILE="/tmp/tmux_task_update.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

# Update only the current session (or all with --update-all)
if [ "${2:-}" = "all" ]; then
    while IFS= read -r session; do
        update_session "$session"
    done < <(tmux list-sessions -F '#S' 2>/dev/null)
else
    current=$(tmux display-message -p '#S' 2>/dev/null || exit 0)
    update_session "$current"
fi
