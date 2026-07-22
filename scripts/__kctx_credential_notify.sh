#!/usr/bin/env bash
set -euo pipefail

readonly mailto="${KCTX_CREDENTIAL_MAILTO:-piotrzan@gmail.com}"
readonly host="${KCTX_CREDENTIAL_HOST:-$(hostname -s)}"
readonly mailer="${KCTX_CREDENTIAL_MAILER:-msmtp}"
readonly kctx_bin="${KCTX_CREDENTIAL_KCTX:-kctx}"
readonly cursor_file="${KCTX_CREDENTIAL_CURSOR_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/kctx/credential-notify.cursor}"

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

events="$($kctx_bin sources events --after "$cursor" --output json)"
next_cursor="$(jq -er '.cursor | select(type == "number")' <<<"$events")"
notifiable="$(
    jq -c '[.events[] | select(
        .to == "auth-required" or
        (.from == "auth-required" and .to == "usable")
    )]' <<<"$events"
)"

if [[ "$(jq 'length' <<<"$notifiable")" -eq 0 ]]; then
    write_cursor "$next_cursor"
    exit 0
fi

if jq -e 'any(.to == "auth-required")' >/dev/null <<<"$notifiable"; then
    subject="[kctx AUTH] $host credentials require login"
else
    subject="[kctx RECOVERED] $host credentials usable again"
fi

{
    printf 'Subject: %s\n' "$subject"
    printf 'From: %s\nTo: %s\n\n' "$mailto" "$mailto"
    printf 'kctx observed credential-domain state changes on %s.\n\n' "$host"
    while IFS= read -r event; do
        domain="$(jq -r '.credential_domain.id' <<<"$event")"
        from="$(jq -r '.from' <<<"$event")"
        to="$(jq -r '.to' <<<"$event")"
        printf 'domain: %s\ntransition: %s -> %s\n' "$domain" "$from" "$to"
        while IFS= read -r source; do
            if source_state="$($kctx_bin sources show "$source" --output json 2>/dev/null)"; then
                remediation="$(jq -er '.source.remediation' <<<"$source_state")"
            else
                remediation="inspect with kctx sources show $source"
            fi
            printf 'source: %s\nfix: %s\n' "$source" "$remediation"
        done < <(jq -r '.sources[]' <<<"$event")
        printf '\n'
    done < <(jq -c '.[]' <<<"$notifiable")
    printf 'Inspect current state with: kctx sources\n'
} | sed -r 's/\x1b\[[0-9;]*m//g' | "$mailer" "$mailto"

write_cursor "$next_cursor"
