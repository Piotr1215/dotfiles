#!/usr/bin/env bash
set -euo pipefail

readonly mailto="piotrzan@gmail.com"
readonly host="${KCTX_HEALTH_HOST:-$(hostname -s)}"
readonly mailer="${KCTX_HEALTH_MAILER:-msmtp}"

if [[ -n "${KCTX_HEALTH_LOG:-}" ]]; then
    log="$KCTX_HEALTH_LOG"
else
    log="$(journalctl --user -u kctx-health.service -n 60 --no-pager -o short-iso)"
fi

{
    printf 'Subject: [kctx FAILED] %s connection refresh\n' "$host"
    printf 'From: %s\nTo: %s\n\n' "$mailto" "$mailto"
    printf 'The kctx background reconciler did not complete successfully on %s.\n' "$host"
    printf 'This alert is reserved for execution, timeout, or state-publication failures.\n\n'
    printf 'Source-specific recovery: kctx sources\n'
    printf 'Inspect with: systemctl --user status kctx-health.service\n'
    printf 'Logs: journalctl --user -u kctx-health.service -n 60\n\n'
    printf '%s\n' "$log"
} | sed -r 's/\x1b\[[0-9;]*m//g' | "$mailer" "$mailto"
