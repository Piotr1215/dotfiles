#!/usr/bin/env bash
# PROJECT: cron-manager
# See: __cron_run.sh (writes the state this reads), __cron_status_dump.sh,
#      __pr_movement_nudge.sh (same delivery path and watermark shape)
#
# Announce a cron job that has just entered `error` state into the live Claude
# pane, so a broken job is known within minutes instead of being noticed hours
# later on the dashboard. Silent when nothing is wrong.
#
# EDGE-TRIGGERED, not level-triggered. `~/.claude/data/cron-error-nudged.json`
# records which jobs have already been announced; a job stays on that list for
# as long as it holds `error`, and is dropped the moment it reports any other
# state. So one broken job produces exactly one line, and produces a second one
# only after it has recovered and broken again. Repeated consecutive failures
# of an already-announced job are deliberately NOT re-announced: the job never
# left error, so nothing transitioned.
#
# COLD START seeds silently. On the very first run (no watermark file at all)
# every job already sitting in error is recorded as announced without sending
# anything. Without this, installing the watcher would fire a burst of stale
# notices for failures Piotr already knows about, e.g. the `exit=143 killed by
# SIGTERM` that the nightly poweroff leaves behind. Mirrors the silent first
# contact in __pr_movement_nudge.sh.
#
# BLIND SPOT, stated rather than papered over: this watcher cannot announce its
# OWN failure. __cron_run.sh writes `state=running` before the wrapped command
# starts, so by the time this body executes its own status file no longer holds
# the previous run's error. It is excluded from the sweep for that reason. Its
# failures surface where every unwatched job's do, on the status table and the
# red argos badge.
#
# Usage:
#   __cron_error_nudge.sh              # live: DM each new error to the pane
#   __cron_error_nudge.sh --dry-run    # print what would be sent, send nothing
#
# Exit codes follow the wrapper contract in ops-cron-manager.md:
#   0  nothing new to say (no-hit)
#   2  announced at least one newly-broken job (hit)
#   1  the watcher itself failed (error)
set -eo pipefail

# env for cron: node on PATH and the bus URL live in the interactive rc.
# shellcheck disable=SC1091
[[ -f "$HOME/.envrc" ]] && source "$HOME/.envrc"

STATE_DIR="${CRON_STATE_DIR:-$HOME/.local/state/cron-jobs}"
NUDGE_STATE="${CRON_ERROR_NUDGE_STATE:-$HOME/.claude/data/cron-error-nudged.json}"
LOCK_FILE="${CRON_ERROR_NUDGE_LOCK:-/tmp/cron-error-nudge.lock}"

# This script's own job name in the crontab, excluded from the sweep. See the
# blind-spot note above.
SELF_JOB="${CRON_ERROR_NUDGE_SELF:-__cron_error_nudge}"

# Delivery: the Node snd binary publishing to the NATS agents comms bus, the
# same transport __auto_triage_nudge.sh and __pr_movement_nudge.sh use to reach
# the live pane. Nothing new is invented here. SND_FROM labels the origin so
# the bus shows the line as watcher-sent rather than human-sent.
SND_NODE_BIN="${SND_NODE_BIN:-/home/decoder/dev/agents-mcp-server/build/snd.js}"
AGENTS_NATS_URL_DEFAULT="nats://nats-nats-tailscale.tail165ec.ts.net:4222"
export AGENTS_NATS_URL="${AGENTS_NATS_URL:-$AGENTS_NATS_URL_DEFAULT}"
export SND_FROM="${SND_FROM:-cron-watch}"
NUDGE_TO="${CRON_ERROR_NUDGE_TO:-triage}"

DRY_RUN=0
case "${1:-}" in
    --dry-run) DRY_RUN=1 ;;
    --live|"") DRY_RUN=0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
esac

# One line per step on stdout, which is the only channel __cron_run.sh captures.
# No private log file: a job that writes solely to its own log hands the wrapper
# nothing and leaves the per-job log at zero bytes.
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# Send one line to the pane over the agents bus.
send_dm() { node "$SND_NODE_BIN" -t "$NUDGE_TO" "$1"; }

# Jobs currently reporting `error`, one name per line. Only the wrapper's own
# states count here: `stale` and `pending` are guesses the dashboard derives
# from log mtimes, not evidence that a run failed.
errored_jobs() {
    local f job
    for f in "$STATE_DIR"/*.json; do
        [ -e "$f" ] || continue
        job=$(basename "$f" .json)
        [ "$job" = "$SELF_JOB" ] && continue
        [ "$(jq -r '.state // ""' "$f" 2>/dev/null)" = "error" ] && printf '%s\n' "$job"
    done
    return 0
}

# The notice itself. One line, scannable, and it names the log so the next move
# is obvious: `__cron_watch.sh <job>` or open the path.
notice_for() {
    local job="$1"
    local f="${STATE_DIR}/${job}.json"
    jq -r '"cron-error: \(.job) exit=\(.exit_code // "?") after \(.duration_s // "?")s :: \(.message // "no message") :: log \(.log_path // "-")"' \
        "$f" 2>/dev/null || printf 'cron-error: %s (state file unreadable)' "$job"
}

main() {
    local mode="LIVE"; [ "$DRY_RUN" -eq 1 ] && mode="DRY-RUN"

    if [ ! -d "$STATE_DIR" ]; then
        log "ERROR: state dir missing: $STATE_DIR"
        echo "SUMMARY: errors=0 announced=0 cleared=0 (no state dir)"
        return 1
    fi

    local current cold_start=0
    current=$(errored_jobs)

    mkdir -p "$(dirname "$NUDGE_STATE")"
    if [ ! -f "$NUDGE_STATE" ]; then
        cold_start=1
        echo '[]' >"$NUDGE_STATE"
    fi

    local announced
    announced=$(jq -c 'if type == "array" then . else [] end' "$NUDGE_STATE" 2>/dev/null || echo '[]')

    # Still-broken jobs stay on the list; recovered ones drop off it. That drop
    # is what re-arms them, and it is the only reset there is.
    local keep cleared_n
    keep=$(jq -cn --argjson a "$announced" --arg cur "$current" \
        '($cur | split("\n") | map(select(. != ""))) as $c | $a | map(select(. as $x | $c | index($x)))')
    cleared_n=$(jq -n --argjson a "$announced" --argjson k "$keep" '($a | length) - ($k | length)')

    # New = in error now, not on the kept list.
    local new_jobs
    new_jobs=$(jq -rn --argjson k "$keep" --arg cur "$current" \
        '($cur | split("\n") | map(select(. != ""))) - $k | .[]')

    local errors_n announced_n=0 job line rc=0 sent=""
    errors_n=$(printf '%s' "$current" | grep -c . || true)

    if [ "$cold_start" -eq 1 ] && [ -n "$new_jobs" ]; then
        log "cold start: seeding ${errors_n} already-broken job(s) silently: $(tr '\n' ' ' <<<"$new_jobs")"
    elif [ -n "$new_jobs" ]; then
        while IFS= read -r job; do
            [ -n "$job" ] || continue
            line=$(notice_for "$job")
            if [ "$DRY_RUN" -eq 1 ]; then
                log "would send to ${NUDGE_TO}: $line"
            else
                if send_dm "$line" >/dev/null 2>&1; then
                    log "sent to ${NUDGE_TO}: $line"
                else
                    log "ERROR: delivery failed for $job"
                    rc=1
                    continue
                fi
            fi
            # Collect the names that actually went out rather than counting
            # them. A failure part-way down the list would otherwise shift the
            # tally against the list order and mark the wrong jobs as told.
            sent+="${job}"$'\n'
            announced_n=$((announced_n + 1))
        done <<<"$new_jobs"
    fi

    # Record only what actually went out. A job whose delivery failed stays off
    # the list so the next tick retries it, rather than being marked told.
    local final tmp
    if [ "$cold_start" -eq 1 ]; then
        final=$(jq -cn --arg cur "$current" '$cur | split("\n") | map(select(. != ""))')
    else
        final=$(jq -cn --argjson k "$keep" --arg sent "$sent" \
            '$k + ($sent | split("\n") | map(select(. != ""))) | unique')
    fi
    tmp=$(mktemp "${NUDGE_STATE}.XXXXXX") || { log "ERROR: mktemp failed"; return 1; }
    printf '%s\n' "$final" >"$tmp" && mv "$tmp" "$NUDGE_STATE"

    # Unconditional summary: the wrapper lifts the last non-blank line into the
    # JSON `message` the dashboard shows, and a tally printed only when
    # something happened is indistinguishable from a job that never ran.
    echo "SUMMARY: mode=$mode errors=$errors_n announced=$announced_n cleared=$cleared_n"

    [ "$rc" -ne 0 ] && return 1
    [ "$announced_n" -gt 0 ] && return 2
    return 0
}

# Serialize: a hand run must not race the scheduled one onto the watermark file.
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "another cron-error-nudge run holds the lock; exiting" >&2
    exit 0
fi
main
