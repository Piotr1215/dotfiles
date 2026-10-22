#!/usr/bin/env bash
# PROJECT: kendra-events
# Spacelift in-app notifications (the bell on loft.app.spacelift.io: "Could
# not notify VCS", "Sandbox ... scheduled for deletion", "GitHub API error")
# as notifications.log records, so Kendra (Gordon while she is down) hears of
# them through notify-watch. Before this nobody read them.
#
# One run reads the 50 most recent notifications through `spacectl api` with
# the loft profile's API key, and appends one record per notification that is
# new, or whose occurrence count grew since the last run (Spacelift folds a
# repeat into the same notification):
#
#   <date time>\tspacelift\t<title>:\tkind:<grouping key> severity:<info|warning|error> target:<target> id:<id> count:<n> link:<url> | <body>
#
# Metadata leads the body so notify-watch's 300 character cut never drops it.
# A notification already dismissed when first seen was handled by someone, so
# it is recorded as seen without a record. The first run (no state) records
# only notifications from the last SPACELIFT_EVENTS_FIRST_HOURS hours and
# seeds the rest, so history never fires.
#
# Run by cron through __cron_run.sh every 5 minutes. Exit codes follow its
# contract: 0 nothing new, 2 appended at least one record, 1 failed (the
# cron-error nudge then tells Kendra once per failure streak). A failed read
# leaves the state untouched, so nothing is lost.
#
# Usage: __spacelift_notifications.sh
#
# Env: SPACELIFT_EVENTS_STATE (state dir), SPACELIFT_EVENTS_LOG (event log),
# SPACELIFT_EVENTS_SPACECTL (spacectl binary), SPACELIFT_EVENTS_URL (the app
# URL links point at), SPACELIFT_EVENTS_FIRST_HOURS (default 24),
# SPACELIFT_EVENTS_KEEP_DAYS (how long a seen id is kept, default 30).
set -eo pipefail

# cron runs with PATH=/usr/bin:/bin.
PATH="${PATH}:/usr/local/bin"

STATE_DIR="${SPACELIFT_EVENTS_STATE:-$HOME/.local/state/spacelift-events}"
EVENT_LOG="${SPACELIFT_EVENTS_LOG:-$HOME/.local/state/notifications.log}"
SPACECTL="${SPACELIFT_EVENTS_SPACECTL:-spacectl}"
APP_URL="${SPACELIFT_EVENTS_URL:-https://loft.app.spacelift.io}"
FIRST_HOURS="${SPACELIFT_EVENTS_FIRST_HOURS:-24}"
KEEP_DAYS="${SPACELIFT_EVENTS_KEEP_DAYS:-30}"

QUERY='query { searchNotifications(input: {first: 50, orderBy: {field: "lastOccurrenceAt", direction: DESC}}) { edges { node { id title body dismissed severity lastOccurrenceAt occurrencesCount target groupingKey } } } }'

# One TSV row per notification: id, count, last occurrence, dismissed,
# severity, kind, target, title, body. Text fields lose tabs and line breaks.
# shellcheck disable=SC2016 # jq program, not shell
JQ_ROWS='def flat: gsub("[\t\r\n]+"; " ");
    .data.searchNotifications.edges[].node
    | [.id, (.occurrencesCount | tostring), (.lastOccurrenceAt | tostring), (.dismissed | tostring),
       (.severity | ascii_downcase), (.groupingKey | gsub("\\s"; "-")), (.target | gsub("\\s"; "-")),
       (.title | flat), (.body | flat)]
    | @tsv'

# link_for <target>: the page a record links to.
link_for() {
    if [[ "$1" == */* ]]; then
        printf '%s/%s' "$APP_URL" "$1"
    else
        printf '%s' "$APP_URL"
    fi
}

# append_record <title> <body>: one record, one write().
append_record() {
    local line
    line="$(printf '%s\tspacelift\t%s:\t%s' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2")"
    line="${line:0:1000}"
    mkdir -p "$(dirname "$EVENT_LOG")"
    printf '%s\n' "$line" >>"$EVENT_LOG"
}

main() {
    local out rows now first=0 hits=0 id count last dismissed severity kind target title body
    local -A seen=()
    mkdir -p "$STATE_DIR"
    exec 8>"$STATE_DIR/lock"
    flock -w 60 8 || {
        echo "ERROR: another run held $STATE_DIR/lock past 60s" >&2
        exit 1
    }

    if ! out="$("$SPACECTL" api "$QUERY" 2>&1)"; then
        echo "ERROR: spacectl api failed: ${out:0:300}" >&2
        exit 1
    fi
    if ! rows="$(jq -er "$JQ_ROWS" <<<"$out" 2>/dev/null)" && ! jq -e '.data.searchNotifications.edges == []' <<<"$out" >/dev/null 2>&1; then
        echo "ERROR: unexpected searchNotifications answer: ${out:0:300}" >&2
        exit 1
    fi

    now="$(date +%s)"
    if [[ -f "$STATE_DIR/seen" ]]; then
        while IFS=$'\t' read -r id count _; do
            [[ -z "$id" ]] || seen[$id]="$count"
        done <"$STATE_DIR/seen"
    else
        first=1
    fi

    while IFS=$'\t' read -r id count last dismissed severity kind target title body; do
        [[ -n "$id" ]] || continue
        if [[ -n "${seen[$id]:-}" ]] && ((count <= seen[$id])); then
            continue
        fi
        if [[ -z "${seen[$id]:-}" && "$dismissed" == true ]] ||
            ((first && last < now - FIRST_HOURS * 3600)); then
            :
        else
            append_record "$title" \
                "kind:${kind} severity:${severity} target:${target} id:${id} count:${count} link:$(link_for "$target") | ${body:0:600}"
            hits=$((hits + 1))
        fi
        seen[$id]="$count"
        printf '%s\t%s\t%s\n' "$id" "$count" "$last" >>"$STATE_DIR/seen.new"
    done <<<"$rows"

    # Keep every id seen within KEEP_DAYS; this run's rows win over older ones.
    touch "$STATE_DIR/seen" "$STATE_DIR/seen.new"
    awk -F'\t' -v cut="$((now - KEEP_DAYS * 86400))" \
        'NR == FNR {fresh[$1] = 1; print; next} !($1 in fresh) && $3 >= cut' \
        "$STATE_DIR/seen.new" "$STATE_DIR/seen" >"$STATE_DIR/seen.tmp"
    mv -f "$STATE_DIR/seen.tmp" "$STATE_DIR/seen"
    rm -f "$STATE_DIR/seen.new"

    echo "SUMMARY: records=$hits"
    ((hits == 0)) || exit 2
}

case "${1:-}" in
"") main ;;
-h | --help) sed -n '2,/^set -eo/p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
*)
    echo "usage: ${0##*/}" >&2
    exit 1
    ;;
esac
