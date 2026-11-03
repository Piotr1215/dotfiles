#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

fake_kctx="$test_dir/kctx"
notifications="$test_dir/state/kctx/notifications.log"
cursor="$test_dir/state/kctx/credential-notify.cursor"
mailer_calls="$test_dir/msmtp-calls"
cat >"$fake_kctx" <<'KCTX'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" != "sources events" ]]; then
    exit 2
fi
after="$4"
if [[ "$KCTX_TEST_EVENT_KIND" == "auth" && "$after" -lt 8 ]]; then
    cat <<'JSON'
{"schema_version":1,"cursor":8,"events":[{"type":"credential-domain-transition","sequence":8,"occurred_at":100,"credential_domain":{"id":"gcloud:opaque","kind":"gcloud"},"from":"usable","to":"auth-required","detail":"interactive authentication is required","sources":["gke/prod"]}]}
JSON
elif [[ "$KCTX_TEST_EVENT_KIND" == "recovery" && "$after" -lt 9 ]]; then
    cat <<'JSON'
{"schema_version":1,"cursor":9,"events":[{"type":"credential-domain-transition","sequence":9,"occurred_at":200,"credential_domain":{"id":"gcloud:opaque","kind":"gcloud"},"from":"auth-required","to":"usable","detail":"credential is usable","sources":["gke/prod"]}]}
JSON
else
    printf '{"schema_version":1,"cursor":%s,"events":[]}\n' "$after"
fi
KCTX
cat >"$test_dir/msmtp" <<'MSMTP'
#!/usr/bin/env bash
printf 'called\n' >>"$KCTX_TEST_MAILER_CALLS"
MSMTP
chmod +x "$fake_kctx" "$test_dir/msmtp"

PATH="$test_dir:$PATH" \
KCTX_TEST_MAILER_CALLS="$mailer_calls" \
KCTX_TEST_EVENT_KIND=auth \
KCTX_NOTIFICATIONS_LOG="$notifications" \
KCTX_CREDENTIAL_KCTX="$fake_kctx" \
KCTX_CREDENTIAL_CURSOR_FILE="$cursor" \
KCTX_CREDENTIAL_HOST=serval \
    "$repo_root/scripts/__kctx_credential_notify.sh"
grep -F 'host=serval credential transitions:' "$notifications"
grep -F '"to":"auth-required"' "$notifications"
grep -F 'Inspect current state with: kctx sources' "$notifications"
[[ "$(stat -c '%a' "$test_dir/state/kctx")" == 700 ]]
[[ "$(stat -c '%a' "$notifications")" == 600 ]]
grep -Fqx '8' "$cursor"

PATH="$test_dir:$PATH" \
KCTX_TEST_MAILER_CALLS="$mailer_calls" \
KCTX_TEST_EVENT_KIND=auth \
KCTX_NOTIFICATIONS_LOG="$notifications" \
KCTX_CREDENTIAL_KCTX="$fake_kctx" \
KCTX_CREDENTIAL_CURSOR_FILE="$cursor" \
KCTX_CREDENTIAL_HOST=serval \
    "$repo_root/scripts/__kctx_credential_notify.sh"
[[ "$(grep -Fc 'credential transitions:' "$notifications")" -eq 1 ]]

PATH="$test_dir:$PATH" \
KCTX_TEST_MAILER_CALLS="$mailer_calls" \
KCTX_TEST_EVENT_KIND=recovery \
KCTX_NOTIFICATIONS_LOG="$notifications" \
KCTX_CREDENTIAL_KCTX="$fake_kctx" \
KCTX_CREDENTIAL_CURSOR_FILE="$cursor" \
KCTX_CREDENTIAL_HOST=serval \
    "$repo_root/scripts/__kctx_credential_notify.sh"
grep -F '"from":"auth-required","to":"usable"' "$notifications"
grep -Fqx '9' "$cursor"

blocked_log="$test_dir/blocked-notifications.log"
mkdir "$blocked_log"
retry_cursor="$test_dir/retry/cursor"
if PATH="$test_dir:$PATH" \
    KCTX_TEST_MAILER_CALLS="$mailer_calls" \
    KCTX_TEST_EVENT_KIND=auth \
    KCTX_NOTIFICATIONS_LOG="$blocked_log" \
    KCTX_CREDENTIAL_KCTX="$fake_kctx" \
    KCTX_CREDENTIAL_CURSOR_FILE="$retry_cursor" \
    KCTX_CREDENTIAL_HOST=serval \
        "$repo_root/scripts/__kctx_credential_notify.sh"; then
    echo 'notification unexpectedly succeeded when the local log was unwritable' >&2
    exit 1
fi
[[ ! -e "$retry_cursor" ]]
[[ ! -e "$mailer_calls" ]]

service="$repo_root/.config/systemd/user/kctx-health.service"
grep -Fqx 'ExecStartPost=-%h/dev/dotfiles/scripts/__kctx_credential_notify.sh' "$service"

printf 'kctx credential local notification test passed\n'
