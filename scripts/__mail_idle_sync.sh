#!/usr/bin/env bash
# PROJECT: mail-attention
# IMAP IDLE dispatcher. goimapnotify (goimapnotify.service, config in
# .config/goimapnotify/goimapnotify.yaml) runs it when a watched Gmail mailbox
# changes, so new and sent mail is synced, indexed and handed to the notmuch
# post-new hook within seconds instead of on a cron timer.
#
# One run:
#   1. takes the mail sync lock, then waits out any mbsync or mailsync that
#      runs without it (Gordon's draft push, mailsync started by hand), so two
#      mbsync processes never touch the store at once
#   2. syncs the mailbox that fired, then the account's INBOX; a connect event
#      on INBOX (goimapnotify issues one at start and after every reconnect)
#      syncs the whole account instead, so mail that arrived while the watcher
#      was down does not wait for the next event
#   3. pops up one mutt-wizard notification per new INBOX file, the same popup
#      mailsync shows, and moves mailsync's lastrun marker so neither path
#      shows a message twice
#   4. runs `notmuch new`, which fires the post-new hook
#
# INBOX is synced last on purpose. The post-new hook decides a message's event
# the first time it sees the message id, and only a copy in INBOX makes one; an
# All Mail or Sent copy indexed before its INBOX copy would swallow the event.
#
# A failed mbsync is retried once: about 4% of syncs hit a socket timeout on
# one of imap.gmail.com's IPv6 addresses, and the retry resolves another.
#
# Usage:
#   __mail_idle_sync.sh <account> <mailbox> [<event>]
#     <account>  mbsync channel, e.g. piotrzan@gmail.com
#     <mailbox>  the box that fired, e.g. INBOX or "[Gmail]/Sent Mail"
#     <event>    goimapnotify's {{.Reason}}; "Synchronize..." marks a connect
#
# Env: MAIL_SYNC_STATE (lock dir), MAIL_SYNC_LASTRUN (mailsync's marker),
# MAIL_SYNC_MAILDIR (mail root), MAIL_SYNC_LOCK_SECS (lock wait, default 600),
# MAIL_SYNC_WAIT_FOR (process names to wait out, default "mbsync mailsync"),
# MAIL_SYNC_WAIT_SECS (how long, default 300), MAILSYNC_MUTE (no popups).
# NOTMUCH_CONFIG picks the database.
set -eo pipefail

STATE_DIR="${MAIL_SYNC_STATE:-$HOME/.local/state/mail-sync}"
LASTRUN="${MAIL_SYNC_LASTRUN:-${XDG_CONFIG_HOME:-$HOME/.config}/mutt/.mailsynclastrun}"
MAIL_ROOT="${MAIL_SYNC_MAILDIR:-$HOME/.local/share/mail}"
LOCK_SECS="${MAIL_SYNC_LOCK_SECS:-600}"
WAIT_FOR="${MAIL_SYNC_WAIT_FOR:-mbsync mailsync}"
WAIT_SECS="${MAIL_SYNC_WAIT_SECS:-300}"

log() {
    printf '%s %s\n' "$(date '+%H:%M:%S.%3N')" "$*"
}

# wait_external: returns once no process named in WAIT_FOR is running, or
# after WAIT_SECS, when mbsync's own box lock is the last guard.
wait_external() {
    local name waited=0 busy
    while :; do
        busy=""
        for name in $WAIT_FOR; do
            pgrep -x "$name" >/dev/null 2>&1 && busy="$name"
        done
        [[ -n "$busy" ]] || return 0
        if ((waited >= WAIT_SECS)); then
            log "WARN: $busy still running after ${WAIT_SECS}s, syncing anyway"
            return 0
        fi
        ((waited == 0)) && log "waiting for $busy to finish"
        sleep 1
        waited=$((waited + 1))
    done
}

# sync_target <mbsync target>: one mbsync run, retried once on failure.
sync_target() {
    local target="$1" start
    start="$(date +%s.%N)"
    if mbsync -q "$target"; then
        log "synced $target in $(elapsed "$start")s"
        return 0
    fi
    log "WARN: mbsync $target failed, retrying"
    if mbsync -q "$target"; then
        log "synced $target on retry in $(elapsed "$start")s"
        return 0
    fi
    log "ERROR: mbsync $target failed twice"
    return 1
}

elapsed() {
    awk -v s="$1" -v e="$(date +%s.%N)" 'BEGIN {printf "%.1f", e - s}'
}

# popup <summary> <body>: mailsync's notify, sent only while a display server
# runs.
popup() {
    [[ -z "$MAILSYNC_MUTE" ]] || return 0
    pgrep -x 'X(|org|wayland)' >/dev/null 2>&1 || return 0
    DISPLAY="${DISPLAY:-:0}" notify-send --app-name="mutt-wizard" "$1" "$2" || true
}

# decode_header <name> <file>: the header's value, MIME decoded, as mailsync
# reads it.
decode_header() {
    sed -n "/^$1:/ s|$1: *|| p" "$2" | perl -CS -MEncode -ne 'print decode("MIME-Header", $_)'
}

# notify_new <account>: mailsync's syncandnotify popups for INBOX files newer
# than the lastrun marker, then moves the marker past them.
notify_new() {
    local account="$1" file from subject
    local -a new=()
    mapfile -t new < <(find "$MAIL_ROOT/$account/"[Ii][Nn][Bb][Oo][Xx]/new/ \
        "$MAIL_ROOT/$account/"[Ii][Nn][Bb][Oo][Xx]/cur/ \
        -type f -newer "$LASTRUN" 2>/dev/null)
    if ((${#new[@]} > 5)); then
        log "${#new[@]} new mail for $account"
        popup "New Mail!" "📬 ${#new[@]} new mail(s) in \`$account\` account."
    elif ((${#new[@]} > 0)); then
        log "${#new[@]} new mail for $account"
        for file in "${new[@]}"; do
            subject="$(decode_header Subject "$file")"
            from="$(decode_header From "$file")"
            from="${from% *}"
            from="${from%\"}"
            from="${from#\"}"
            popup "📧$from:" "$subject"
        done
    fi
    mkdir -p "$(dirname "$LASTRUN")"
    touch "$LASTRUN"
}

main() {
    local account="$1" mailbox="$2" event="${3:-}" rc=0 start target
    local -a targets=()
    if [[ -z "$account" || -z "$mailbox" ]]; then
        echo "usage: ${0##*/} <account> <mailbox> [<event>]" >&2
        exit 1
    fi
    if [[ "$mailbox" == INBOX && "$event" == Synchronize* ]]; then
        targets=("$account")
    elif [[ "$mailbox" == INBOX ]]; then
        targets=("$account:INBOX")
    else
        targets=("$account:$mailbox" "$account:INBOX")
    fi

    mkdir -p "$STATE_DIR"
    start="$(date +%s.%N)"
    exec 9>"$STATE_DIR/lock"
    flock -w "$LOCK_SECS" 9 || {
        log "ERROR: $STATE_DIR/lock held past ${LOCK_SECS}s"
        exit 1
    }
    log "event ${event:-New Email} on $account $mailbox, lock after $(elapsed "$start")s"
    wait_external

    for target in "${targets[@]}"; do
        sync_target "$target" || rc=1
    done
    notify_new "$account"

    # A file, not a pipe: a hook child that outlives notmuch must not hold
    # goimapnotify's capture of this script's stdout open.
    if ! notmuch new --quiet >"$STATE_DIR/notmuch-new.out" 2>&1; then
        log "ERROR: notmuch new failed: $(head -c 300 "$STATE_DIR/notmuch-new.out")"
        rc=1
    fi
    log "done in $(elapsed "$start")s"
    exit "$rc"
}

main "$@"
