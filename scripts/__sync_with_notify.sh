#!/usr/bin/env bash

# Log file for debugging
LOG_FILE="/tmp/github-issue-sync.log"

# Set up environment for the sync script
if [[ -f "$HOME/.envrc" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.envrc"
else
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: ERROR - ~/.envrc not found" >> "$LOG_FILE"
    dunstify -u critical -A "view,View Log" "✗ Sync failed" "$HOME/.envrc not found\nLog: $LOG_FILE"
    exit 1
fi

# Validate required environment variables
if [[ -z "$LINEAR_API_KEY" ]] || [[ -z "$LINEAR_USER_ID" ]]; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: ERROR - Required environment variables not set" >> "$LOG_FILE"
    dunstify -u critical -A "view,View Log" "✗ Sync failed" "LINEAR_API_KEY or LINEAR_USER_ID not set\nLog: $LOG_FILE"
    exit 1
fi

# Set display variables for notifications
export DISPLAY=:1
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

# Run the sync script and log output
if ! /home/decoder/dev/dotfiles/scripts/__github_issue_sync.sh >> "$LOG_FILE" 2>&1; then
    # Get last 5 lines for context
    error_context=$(tail -n 5 "$LOG_FILE")

    # Try to extract a concise error message
    error_msg=$(echo "$error_context" | grep -i "error" | head -n 1 || echo "Unknown error occurred")

    # Show notification with action to view full log
    action=$(dunstify -u critical \
        -A "view,View Full Log" \
        -A "tail,Tail Log" \
        "✗ Sync failed" \
        "$error_msg\n\nLog: file://$LOG_FILE")

    # Handle user action
    case "$action" in
        view)
            # Open log in default text editor or less
            if command -v xdg-open &> /dev/null; then
                xdg-open "$LOG_FILE" &
            else
                # Fallback: open in terminal with less
                x-terminal-emulator -e less "$LOG_FILE" &
            fi
            ;;
        tail)
            # Open terminal tailing the log
            x-terminal-emulator -e bash -c "tail -f '$LOG_FILE'; exec bash" &
            ;;
    esac

    exit 1
fi

# Success - keep log clean (last 1000 lines only)
tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null || true
