#!/usr/bin/env bash

# Log file for debugging. Both paths are overridable for the tests.
LOG_FILE="${SYNC_LOG_FILE:-/tmp/github-issue-sync.log}"
SYNC_SCRIPT="${SYNC_SCRIPT:-/home/decoder/dev/dotfiles/scripts/__github_issue_sync.sh}"

# Keep the existing log on failure, but bound it on every exit.
run_log=$(mktemp "${LOG_FILE}.run.XXXXXX") || exit 1
# shellcheck disable=SC2317 # Called by the EXIT trap.
cleanup_log() {
    tail -n 1000 "$LOG_FILE" > "${run_log}.tail" && mv "${run_log}.tail" "$LOG_FILE"
    rm -f "$run_log" "${run_log}.tail"
}
trap cleanup_log EXIT

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
export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

# Run the sync script and log output
# Capture rather than redirect straight to the file: the cron wrapper reads
# stdout, so redirecting everything to /tmp left the per-job log empty on every
# run. The file still receives the full transcript; stdout carries the outcome.
# tee rather than capture. Command substitution held the entire run in memory
# and emitted nothing until the inner sync exited some 65 seconds later, so the
# log stayed blank for the whole time the work was actually happening. Teeing
# streams to the file and to stdout at once, which is what lets the cron
# wrapper's log fill as the sync progresses instead of all at the end.
"$SYNC_SCRIPT" 2>&1 | tee -a "$LOG_FILE" "$run_log"
sync_rc=${PIPESTATUS[0]}
if [ "$sync_rc" -ne 0 ]; then
    # Get last 5 lines for context
    error_context=$(tail -n 5 "$run_log")

    # Try to extract a concise error message
    error_msg=$(printf '%s\n' "$error_context" | grep -iE 'error|failed|not found' | tail -n 1)
    [[ -n "$error_msg" ]] || error_msg="sync exited with status $sync_rc: $(printf '%s\n' "$error_context" | tail -n 1)"
    printf '[%s]: FAILED: %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$error_msg" | tee -a "$LOG_FILE"

    # Show notification with action to view full log
    action=$(dunstify -u critical \
        -A "view,View Full Log" \
        -A "tail,Tail Log" \
        "✗ Sync failed" \
        "$error_msg\n\nLog: file://$LOG_FILE")

    # Handle user action. Viewers get their own stdio: cron pipes this script
    # into the job log, and a viewer that inherits the pipe keeps the job
    # "running" until it closes. cosmic-edit did that for the whole 2026-10-14
    # morning and wrote its theme errors into the cron log as it went.
    case "$action" in
        view)
            # Open log in default text editor or less
            if command -v xdg-open &> /dev/null; then
                xdg-open "$LOG_FILE" >/dev/null 2>&1 &
            else
                # Fallback: open in terminal with less
                x-terminal-emulator -e less "$LOG_FILE" >/dev/null 2>&1 &
            fi
            ;;
        tail)
            # Open terminal tailing the log
            x-terminal-emulator -e bash -c "tail -f '$LOG_FILE'; exec bash" >/dev/null 2>&1 &
            ;;
    esac

    exit 1
fi

# One line of outcome on stdout: a silent success is indistinguishable from a
# run that never happened once the transcript goes to a different file.
printf '[%s]: OK: github issue sync completed (exit %s)\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$sync_rc" | tee -a "$run_log"

# A successful run replaces stale failures with its own transcript.
cp "$run_log" "$LOG_FILE"

# Nudge is now triggered from inside __github_issue_sync.sh so both cron
# and manual invocations produce one — see triage thread 2026-05-12.

# Terminal status is the cron wrapper's state channel: 0 no-hit, 2 hit,
# anything else error. Do not let the last command decide it.
exit 0
