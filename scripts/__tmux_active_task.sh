#!/usr/bin/env bash
# Display linear issue, mpv track, or date/time for tmux status bar
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
        echo "$(date +"%a %H:%M")"
    fi
    exit 0
fi

# --- Async update mode (called by tmux hooks in background) ---

truncate_desc() {
    local desc="$1" max="${2:-50}"
    if [ ${#desc} -gt "$max" ]; then
        echo "${desc:0:$((max - 3))}..."
    else
        echo "$desc"
    fi
}

get_agent_issue() {
    command -v task &> /dev/null || return 0
    local session="$1"
    local linear_id
    if [[ "$session" =~ ([a-zA-Z]+-[0-9]+)$ ]]; then
        linear_id=$(echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')
    fi
    [ -z "$linear_id" ] && return 0
    local desc
    desc=$(task rc.verbose=nothing "linear_issue_id:$linear_id" export 2>/dev/null | jq -r '.[0].description // empty' 2>/dev/null) || true
    [ -n "$desc" ] && echo "📋 $desc"
}

get_mpv_track() {
    pgrep -x mpv > /dev/null || return 0

    local socket_dir="${HOME}/.mpv_sockets"
    local title=""

    if [ -d "$socket_dir" ]; then
        for socket in "$socket_dir"/*; do
            [ -S "$socket" ] || continue
            title=$(echo '{"command": ["get_property", "media-title"]}' | socat - "$socket" 2>/dev/null | jq -r '.data // empty' 2>/dev/null) || true
            [ -z "$title" ] && title=$(echo '{"command": ["get_property", "filename"]}' | socat - "$socket" 2>/dev/null | jq -r '.data // empty' 2>/dev/null) || true
            [ -n "$title" ] && break
        done
    fi

    [ -z "$title" ] && title=$(pgrep -a mpv | head -1 | sed 's/.*mpv //' | sed 's/^.*\///' | cut -c1-30) || true

    if [ -n "$title" ]; then
        echo "🎵 $(truncate_desc "$title" 25)"
    else
        echo "🎵 Playing"
    fi
}

update_session() {
    local session="$1"
    local datetime="$(date +"%a %H:%M")"
    local prefix=""

    prefix=$(get_agent_issue "$session")
    if [ -z "$prefix" ]; then
        prefix=$(get_mpv_track)
    fi

    if [ -n "$prefix" ]; then
        echo "$prefix | $datetime" > "$CACHE_DIR/${session}"
    else
        echo "$datetime" > "$CACHE_DIR/${session}"
    fi
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
