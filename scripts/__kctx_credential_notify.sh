#!/usr/bin/env bash
set -euo pipefail

readonly host="${KCTX_CREDENTIAL_HOST:-$(hostname -s)}"
readonly kctx_bin="${KCTX_CREDENTIAL_KCTX:-kctx}"
readonly cursor_file="${KCTX_CREDENTIAL_CURSOR_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/kctx/credential-notify.cursor}"
readonly notifications_log="${KCTX_NOTIFICATIONS_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/kctx/notifications.log}"

write_cursor() {
    local cursor="$1"
    local cursor_dir
    local temporary
    cursor_dir="$(dirname "$cursor_file")"
    mkdir -p "$cursor_dir"
    chmod 700 "$cursor_dir"
    temporary="$(mktemp "$cursor_dir/.credential-notify.cursor.XXXXXX")"
    chmod 600 "$temporary"
    printf '%s\n' "$cursor" >"$temporary"
    mv "$temporary" "$cursor_file"
}

cursor=0
if [[ -f "$cursor_file" ]]; then
    cursor="$(<"$cursor_file")"
fi
if [[ ! "$cursor" =~ ^[0-9]+$ ]]; then
    printf 'invalid kctx credential notification cursor: %s\n' "$cursor" >&2
    exit 1
fi

events="$("$kctx_bin" sources events --after "$cursor" --output json)"
next_cursor="$(jq -er '.cursor | select(type == "number")' <<<"$events")"
notifiable="$(jq -c '[.events[] | select(.to == "auth-required" or (.from == "auth-required" and .to == "usable"))]' <<<"$events")"

if [[ "$(jq 'length' <<<"$notifiable")" -eq 0 ]]; then
    write_cursor "$next_cursor"
    exit 0
fi

log_dir="$(dirname "$notifications_log")"
umask 077
mkdir -p "$log_dir"
chmod 700 "$log_dir"
touch "$notifications_log"
chmod 600 "$notifications_log"
{
    printf '%s host=%s credential transitions:\n' "$(date --iso-8601=seconds)" "$host"
    jq -c '.[]' <<<"$notifiable"
    printf 'Inspect current state with: kctx sources\n'
} >>"$notifications_log"
chmod 600 "$notifications_log"
write_cursor "$next_cursor"
