#!/usr/bin/env bash
set -euo pipefail

readonly host="${KCTX_HEALTH_HOST:-$(hostname -s)}"
readonly notifications_log="${KCTX_NOTIFICATIONS_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/kctx/notifications.log}"

if [[ -n "${KCTX_HEALTH_LOG:-}" ]]; then
    log="$KCTX_HEALTH_LOG"
else
    log="$(journalctl --user -u kctx-health.service -n 60 --no-pager -o short-iso || true)"
fi

log_dir="$(dirname "$notifications_log")"
umask 077
mkdir -p "$log_dir"
chmod 700 "$log_dir"
touch "$notifications_log"
chmod 600 "$notifications_log"
{
    printf '%s host=%s health refresh failed\n' "$(date --iso-8601=seconds)" "$host"
    printf 'This alert is reserved for execution, timeout, or state-publication failures.\n\n'
    printf 'Source-specific recovery: kctx sources\n'
    printf 'Inspect with: systemctl --user status kctx-health.service\n'
    printf 'Logs: journalctl --user -u kctx-health.service -n 60\n\n'
    printf '%s\n' "$log"
} | sed -r 's/\x1b\[[0-9;]*m//g' >>"$notifications_log"
chmod 600 "$notifications_log"
