#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

fake_kctx="$test_dir/kctx"
fake_mailer="$test_dir/msmtp"
message="$test_dir/message.eml"
cursor="$test_dir/state/cursor"

cat >"$fake_kctx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == "sources events" ]]; then
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
elif [[ "$1 $2" == "sources show" ]]; then
    printf '{"schema_version":1,"source":{"remediation":"gcloud auth login, then kctx connections refresh"}}\n'
else
    exit 2
fi
EOF

cat >"$fake_mailer" <<'EOF'
#!/usr/bin/env bash
cat >>"$KCTX_TEST_MESSAGE"
EOF
chmod +x "$fake_kctx" "$fake_mailer"

KCTX_TEST_EVENT_KIND=auth \
KCTX_TEST_MESSAGE="$message" \
KCTX_CREDENTIAL_KCTX="$fake_kctx" \
KCTX_CREDENTIAL_MAILER="$fake_mailer" \
KCTX_CREDENTIAL_CURSOR_FILE="$cursor" \
KCTX_CREDENTIAL_HOST=serval \
    "$repo_root/scripts/__kctx_credential_notify.sh"

grep -Fqx 'Subject: [kctx AUTH] serval credentials require login' "$message"
grep -Fqx 'source: gke/prod' "$message"
grep -Fqx 'fix: gcloud auth login, then kctx connections refresh' "$message"
grep -Fqx '8' "$cursor"

KCTX_TEST_EVENT_KIND=auth \
KCTX_TEST_MESSAGE="$message" \
KCTX_CREDENTIAL_KCTX="$fake_kctx" \
KCTX_CREDENTIAL_MAILER="$fake_mailer" \
KCTX_CREDENTIAL_CURSOR_FILE="$cursor" \
KCTX_CREDENTIAL_HOST=serval \
    "$repo_root/scripts/__kctx_credential_notify.sh"

[[ "$(grep -Fc 'Subject:' "$message")" -eq 1 ]]

recovery_message="$test_dir/recovery.eml"
KCTX_TEST_EVENT_KIND=recovery \
KCTX_TEST_MESSAGE="$recovery_message" \
KCTX_CREDENTIAL_KCTX="$fake_kctx" \
KCTX_CREDENTIAL_MAILER="$fake_mailer" \
KCTX_CREDENTIAL_CURSOR_FILE="$cursor" \
KCTX_CREDENTIAL_HOST=serval \
    "$repo_root/scripts/__kctx_credential_notify.sh"

grep -Fqx 'Subject: [kctx RECOVERED] serval credentials usable again' "$recovery_message"
grep -Fqx '9' "$cursor"

failing_mailer="$test_dir/failing-mailer"
retry_cursor="$test_dir/retry/cursor"
cat >"$failing_mailer" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
chmod +x "$failing_mailer"
if KCTX_TEST_EVENT_KIND=auth \
    KCTX_TEST_MESSAGE="$test_dir/failed.eml" \
    KCTX_CREDENTIAL_KCTX="$fake_kctx" \
    KCTX_CREDENTIAL_MAILER="$failing_mailer" \
    KCTX_CREDENTIAL_CURSOR_FILE="$retry_cursor" \
    KCTX_CREDENTIAL_HOST=serval \
        "$repo_root/scripts/__kctx_credential_notify.sh"; then
    echo 'notification unexpectedly succeeded with a failing mailer' >&2
    exit 1
fi
[[ ! -e "$retry_cursor" ]]

service="$repo_root/.config/systemd/user/kctx-health.service"
grep -Fqx 'ExecStartPost=-%h/dev/dotfiles/scripts/__kctx_credential_notify.sh' "$service"

echo 'kctx credential notification test passed'
