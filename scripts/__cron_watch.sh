#!/usr/bin/env bash
# PROJECT: cron-manager
#
# Live views over the cron-job state directory, so a run can be watched while
# it happens instead of being reconstructed afterwards from the dashboard.
#
#   __cron_watch.sh              redraw the status table whenever state changes
#   __cron_watch.sh <job>        follow that job's log live (tail -F semantics)
#   __cron_watch.sh -l           list jobs that have state on disk
#
# Read-only, like __cron_status_dump.sh: nothing here writes crontab, state,
# or logs. It is a viewer, not an actor.
set -eo pipefail

STATE_DIR="${CRON_STATE_DIR:-$HOME/.local/state/cron-jobs}"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DUMP="${CRON_STATUS_DUMP:-$SCRIPT_DIR/__cron_status_dump.sh}"

TAIL_LINES="${CRON_WATCH_TAIL:-40}"
# Redraw the table this often even when no state file moved. The table's LAST
# and NEXT columns are relative ("4m", "<1m"), so they drift while the files
# sit perfectly still. A purely event-driven view would go quietly stale on an
# idle machine, which is the one state it most needs to render honestly.
IDLE_REDRAW_SECS="${CRON_WATCH_IDLE_REDRAW:-30}"
# One run touches its .log several times and its .json twice. Coalesce that
# burst into a single redraw rather than flickering through it.
DEBOUNCE_SECS="${CRON_WATCH_DEBOUNCE:-0.3}"

usage() {
    cat >&2 <<'EOF'
usage: __cron_watch.sh [<job> | -l | -h]

  (no args)   watch the status table, redrawn on state change
  <job>       follow ~/.local/state/cron-jobs/<job>.log live
  -l          list jobs that have state on disk
  -h          this help

env:
  CRON_STATE_DIR          state dir to read (default ~/.local/state/cron-jobs)
  CRON_WATCH_TAIL         backlog lines when following (default 40)
  CRON_WATCH_IDLE_REDRAW  idle table redraw seconds (default 30)
EOF
}

# Job names that have state on disk. Derived from the .json files rather than
# from crontab: this view follows what the wrapper actually recorded, and a job
# removed from crontab still has a log worth reading.
list_jobs() {
    local f
    for f in "$STATE_DIR"/*.json; do
        [ -e "$f" ] || continue
        basename "$f" .json
    done
}

# Reject anything that could escape STATE_DIR. Job names come off a crontab
# line in every other tool here, but this one is typed by hand.
valid_job_name() {
    case "$1" in
        ""|*/*|.|..|.*) return 1 ;;
        *) return 0 ;;
    esac
}

# Follow one job's log. `tail -F` (--follow=name --retry), never `-f`: the
# wrapper rotates at 1MB with `mv log log.1` and then appends to a fresh inode,
# and a plain `-f` would sit on the renamed file forever, showing nothing while
# the job runs. -F reopens by name and picks the new file up.
follow_job() {
    local job="$1"
    local log="${STATE_DIR}/${job}.log"

    if ! valid_job_name "$job"; then
        printf 'not a job name: %s\n' "$job" >&2
        return 1
    fi

    if [ ! -e "$log" ] && [ ! -e "${STATE_DIR}/${job}.json" ]; then
        printf 'no state for job "%s". Known jobs:\n' "$job" >&2
        list_jobs >&2
        return 1
    fi

    # State line first, so the follow starts with context rather than with a
    # naked log tail. Same field names the dashboard and argos widget read.
    if [ -f "${STATE_DIR}/${job}.json" ]; then
        jq -r '"\(.job): state=\(.state) exit=\(.exit_code // "-") duration=\(.duration_s // "-")s :: \(.message // "")"' \
            "${STATE_DIR}/${job}.json" 2>/dev/null || true
    fi
    if [ ! -e "$log" ]; then
        printf 'no log yet, waiting for the first run to write one...\n'
    fi
    printf -- '--- following %s (ctrl-c to stop) ---\n' "$log"

    # exec so ctrl-c goes straight to tail and leaves no wrapper behind.
    exec tail -n "$TAIL_LINES" -F "$log" 2>/dev/null
}

# Full-screen redraw of the status table.
render_table() {
    local rc=0
    printf '\033[H\033[2J'
    printf 'cron status @ %s   (watching %s, ctrl-c to stop)\n\n' \
        "$(date '+%H:%M:%S')" "$STATE_DIR"
    "$DUMP" || rc=$?
    [ "$rc" -eq 0 ] || printf '\n!! status dump failed (exit %s)\n' "$rc"
}

# Last-resort table loop for a machine without inotify. `watch` re-execs the
# dump itself and owns the screen, so it replaces our own render loop entirely.
poll_table() {
    printf 'falling back to polling every %ss\n' "$IDLE_REDRAW_SECS" >&2
    if command -v watch >/dev/null 2>&1; then
        exec watch -t -n "$IDLE_REDRAW_SECS" "$DUMP"
    fi
    while :; do
        render_table
        sleep "$IDLE_REDRAW_SECS"
    done
}

# Watch the whole table, event-driven where the kernel can tell us.
#
# inotifywait watches the DIRECTORY, not a file list. That matters: a job's
# first wrapped run creates its .json, and `entr` (also installed here) fixes
# its file set when it starts, so a newly adopted job would never show up
# without a restart. Watching the directory catches creates, writes, and the
# rotation rename alike.
#
# -t turns the wait into the idle redraw: exit 2 means "nothing happened in
# IDLE_REDRAW_SECS", which is the cue to repaint the drifting age columns.
watch_table() {
    local rc

    if [ ! -d "$STATE_DIR" ]; then
        printf 'state dir does not exist: %s\n' "$STATE_DIR" >&2
        return 1
    fi

    render_table

    if command -v inotifywait >/dev/null 2>&1; then
        while :; do
            rc=0
            inotifywait -qq -t "$IDLE_REDRAW_SECS" \
                -e close_write,create,moved_to,move_self,delete \
                "$STATE_DIR" >/dev/null 2>&1 || rc=$?
            # 0 = an event landed, 2 = the idle timeout. Anything else means
            # inotify itself is unusable (watch limit, unsupported fs), and
            # retrying would spin, so hand over to polling instead.
            if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
                printf '\ninotifywait failed (exit %s)\n' "$rc" >&2
                break
            fi
            [ "$rc" -eq 0 ] && sleep "$DEBOUNCE_SECS"
            render_table
        done
    fi

    poll_table
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    -l|--list) list_jobs; exit 0 ;;
    -*) usage; exit 1 ;;
    "") watch_table ;;
    *) follow_job "$1" ;;
esac
