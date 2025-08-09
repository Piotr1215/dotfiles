#!/usr/bin/env bash
# Display active/started taskwarrior task, approved PRs, and time for tmux status bar
set -eo pipefail

# Check if we're in time off mode
is_time_off() {
    # First check if it's a weekend
    local current_day=$(date +"%A")
    if [[ "$current_day" == "Saturday" ]] || [[ "$current_day" == "Sunday" ]]; then
        return 0
    fi
    
    # Also check boot.sh for manual timeoff setting
    local boot_script="/home/decoder/dev/dotfiles/scripts/__boot.sh"
    if [ -f "$boot_script" ]; then
        local timeoff=$(grep -E '^timeoff=' "$boot_script" | cut -d'=' -f2)
        if [ "$timeoff" = "1" ]; then
            return 0
        fi
    fi
    return 1
}

# Get the active (started) task or last worked on task
get_task_status() {
    # Check if task command exists
    if ! command -v task &> /dev/null; then
        echo ""
        return
    fi
    
    # First check for currently active task (has start but no end)
    local active_task=$(task rc.verbose=nothing status:pending start.any: export 2>/dev/null | jq -r 'sort_by(.start) | reverse | .[0]' 2>/dev/null)
    
    if [ -n "$active_task" ] && [ "$active_task" != "null" ]; then
        # Extract linear_issue_id from active task
        local linear_id=$(echo "$active_task" | jq -r '.linear_issue_id // empty')
        
        if [ -n "$linear_id" ]; then
            echo "CUR: $linear_id"
            return
        fi
    fi
    
    # No active task, look for last completed task with linear_issue_id
    local last_completed=$(task rc.verbose=nothing status:completed linear_issue_id.any: export 2>/dev/null | jq -r 'sort_by(.end) | reverse | .[0]' 2>/dev/null)
    
    if [ -n "$last_completed" ] && [ "$last_completed" != "null" ]; then
        local linear_id=$(echo "$last_completed" | jq -r '.linear_issue_id // empty')
        if [ -n "$linear_id" ]; then
            echo "LAST: $linear_id"
            return
        fi
    fi
    
    echo ""
}

# Get count of approved PRs with change detection
get_approved_prs() {
    if ! command -v task &> /dev/null; then
        echo ""
        return
    fi
    
    # Count tasks with pr_approved tag
    local approved_count=$(task rc.verbose=nothing +pr_approved status:pending count 2>/dev/null)
    
    if [ -n "$approved_count" ] && [ "$approved_count" -gt 0 ]; then
        # Check for changes
        local state_file="/tmp/tmux_pr_count_${USER}"
        local prev_count=0
        local indicator=""
        
        if [ -f "$state_file" ]; then
            prev_count=$(cat "$state_file" 2>/dev/null || echo 0)
        fi
        
        # Save current count
        echo "$approved_count" > "$state_file"
        
        # Add animation indicator for changes
        local animation_file="/tmp/tmux_pr_animation_${USER}"
        local direction_file="/tmp/tmux_pr_direction_${USER}"
        
        if [ "$approved_count" -gt "$prev_count" ]; then
            # New PR approved - show up arrow briefly
            echo "$(date +%s)" > "$animation_file"
            echo "up" > "$direction_file"
            indicator=" ↑"
        elif [ "$approved_count" -lt "$prev_count" ]; then
            # PR merged/removed - show down arrow briefly
            echo "$(date +%s)" > "$animation_file"
            echo "down" > "$direction_file"
            indicator=" ↓"
        else
            # Check if we should still show animation (within 5 seconds)
            if [ -f "$animation_file" ]; then
                local animation_time=$(cat "$animation_file" 2>/dev/null || echo 0)
                local current_time=$(date +%s)
                local time_diff=$((current_time - animation_time))
                
                if [ "$time_diff" -lt 5 ]; then
                    # Show the stored direction
                    if [ -f "$direction_file" ]; then
                        local direction=$(cat "$direction_file")
                        if [ "$direction" = "up" ]; then
                            indicator=" ↑"
                        elif [ "$direction" = "down" ]; then
                            indicator=" ↓"
                        fi
                    fi
                else
                    # Animation expired, clean up
                    rm -f "$animation_file" "$direction_file"
                fi
            fi
        fi
        
        echo "PR ✅ ${approved_count}${indicator}"
        return
    fi
    echo ""
}

# Get relaxing time-off info
get_time_off_status() {
    local day=$(date +"%a")
    local week_num=$(date +"%V")
    
    # Check if mpv is playing something
    local mpv_status=""
    if pgrep -x mpv > /dev/null; then
        # Try to get media title from mpv IPC socket
        local socket_dir="${HOME}/.mpv_sockets"
        local title=""
        
        # Check for any socket in the directory
        if [ -d "$socket_dir" ]; then
            for socket in "$socket_dir"/*; do
                if [ -S "$socket" ]; then
                    # Get media title from mpv
                    title=$(echo '{"command": ["get_property", "media-title"]}' | socat - "$socket" 2>/dev/null | jq -r '.data // empty' 2>/dev/null)
                    if [ -z "$title" ]; then
                        # Fallback to filename
                        title=$(echo '{"command": ["get_property", "filename"]}' | socat - "$socket" 2>/dev/null | jq -r '.data // empty' 2>/dev/null)
                    fi
                    [ -n "$title" ] && break
                fi
            done
        fi
        
        # If no socket or couldn't get title, just show mpv is running
        if [ -z "$title" ]; then
            # Try to get from process arguments
            title=$(pgrep -a mpv | head -1 | sed 's/.*mpv //' | sed 's/^.*\///' | cut -c1-30)
        fi
        
        if [ -n "$title" ]; then
            # Truncate if too long
            if [ ${#title} -gt 25 ]; then
                title="${title:0:22}..."
            fi
            mpv_status="🎵 $title"
        else
            mpv_status="🎵 Playing"
        fi
    fi
    
    # Only show mpv status if something is playing
    if [ -n "$mpv_status" ]; then
        echo "$mpv_status | $day W$week_num"
    else
        # Nothing playing - just show day and week
        echo "$day W$week_num"
    fi
}

# Main - combine all info
current_time=$(date +"%H:%M")

# Check if in time off mode
if is_time_off; then
    # Time off mode - show relaxing info
    time_status=$(get_time_off_status)
    echo "$time_status | $current_time"
else
    # Work mode - show tasks and PRs
    task_info=$(get_task_status)
    approved_prs=$(get_approved_prs)
    
    # Build output string
    output=""
    
    if [ -n "$task_info" ]; then
        output="📋 $task_info"
    fi
    
    if [ -n "$approved_prs" ]; then
        if [ -n "$output" ]; then
            output="$output | $approved_prs"
        else
            output="$approved_prs"
        fi
    fi
    
    if [ -n "$output" ]; then
        echo "$output | $current_time"
    else
        echo "$current_time"
    fi
fi