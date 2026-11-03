#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

notifications="$test_dir/state/kctx/notifications.log"
mailer_calls="$test_dir/msmtp-calls"
cat >"$test_dir/msmtp" <<'MSMTP'
#!/usr/bin/env bash
printf 'called\n' >>"$KCTX_TEST_MAILER_CALLS"
MSMTP
chmod +x "$test_dir/msmtp"

PATH="$test_dir:$PATH" \
KCTX_TEST_MAILER_CALLS="$mailer_calls" \
KCTX_NOTIFICATIONS_LOG="$notifications" \
KCTX_HEALTH_HOST="serval" \
KCTX_HEALTH_LOG=$'refresh failed: \033[31mexpired login\033[0m' \
    "$repo_root/scripts/__kctx_health_notify.sh"
grep -F 'host=serval health refresh failed' "$notifications"
grep -Fqx 'refresh failed: expired login' "$notifications"
[[ "$(stat -c '%a' "$test_dir/state/kctx")" == 700 ]]
[[ "$(stat -c '%a' "$notifications")" == 600 ]]
if grep -q $'\033' "$notifications"; then
    echo 'notification log contains an ANSI escape' >&2
    exit 1
fi
[[ ! -e "$mailer_calls" ]]

service="$repo_root/.config/systemd/user/kctx-health.service"
alert="$repo_root/.config/systemd/user/kctx-health-alert.service"
grep -Fqx 'OnFailure=kctx-health-alert.service' "$service"
grep -Fqx 'ExecStart=%h/dev/dotfiles/scripts/__kctx_health_notify.sh' "$alert"
grep -Fqx 'Description=Record a kctx connection refresh failure' "$alert"
if rg -n 'msmtp|sendmail|mailx|mailto|KCTX_HEALTH_MAILER|KCTX_CREDENTIAL_MAILER' \
    "$repo_root/scripts/__kctx_health_notify.sh" \
    "$repo_root/scripts/__kctx_credential_notify.sh" \
    "$repo_root/.config/systemd/user/kctx-health.service" \
    "$repo_root/.config/systemd/user/kctx-health-alert.service"; then
    echo 'kctx notification sender still contains an email path' >&2
    exit 1
fi

printf 'kctx health local notification test passed\n'
