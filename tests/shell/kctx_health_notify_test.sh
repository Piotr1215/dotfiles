#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

fake_mailer="$test_dir/msmtp"
message="$test_dir/message.eml"
args="$test_dir/args"
cat >"$fake_mailer" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$KCTX_TEST_ARGS"
cat >"$KCTX_TEST_MESSAGE"
EOF
chmod +x "$fake_mailer"

KCTX_HEALTH_MAILER="$fake_mailer" \
KCTX_TEST_ARGS="$args" \
KCTX_TEST_MESSAGE="$message" \
KCTX_HEALTH_HOST="serval" \
KCTX_HEALTH_LOG=$'refresh failed: \033[31mexpired login\033[0m' \
    "$repo_root/scripts/__kctx_health_notify.sh"

grep -Fqx 'piotrzan@gmail.com' "$args"
grep -Fqx 'Subject: [kctx FAILED] serval connection refresh' "$message"
grep -Fqx 'From: piotrzan@gmail.com' "$message"
grep -Fqx 'To: piotrzan@gmail.com' "$message"
grep -Fqx 'The kctx background reconciler did not complete successfully on serval.' "$message"
grep -Fqx 'Source-specific recovery: kctx sources' "$message"
grep -Fqx 'refresh failed: expired login' "$message"
if grep -Fq 'at least one source or reconciliation step is degraded' "$message"; then
    echo 'failure notification conflates handled degradation with reconciliation failure' >&2
    exit 1
fi
if grep -q $'\033' "$message"; then
    echo 'notification contains an ANSI escape' >&2
    exit 1
fi

service="$repo_root/.config/systemd/user/kctx-health.service"
alert="$repo_root/.config/systemd/user/kctx-health-alert.service"
grep -Fqx 'OnFailure=kctx-health-alert.service' "$service"
grep -Fqx 'StartLimitIntervalSec=6h' "$alert"
grep -Fqx 'StartLimitBurst=1' "$alert"

echo 'kctx health notification test passed'
