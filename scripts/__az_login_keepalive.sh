#!/usr/bin/env bash
# __az_login_keepalive.sh - keep the Azure CLI login from expiring while idle.
#
# Entra expires an Azure CLI refresh token that goes unused for too long. On
# 24 Nov 2026 the Loft Labs tenant failed with "AADSTS700082: The refresh token
# has expired due to inactivity ... inactive for 12:00:00", which forces a new
# interactive `az login`. AADSTS700082 is the inactivity code; a Conditional
# Access sign-in frequency would have been AADSTS70043. So using the token often
# enough keeps the session alive.
#
# The CLI's ARM access token lives about 75 minutes, so a run every 4 hours
# always finds it expired and redeems the refresh token, which resets the idle
# window. Run by az-login-keepalive.timer every 4 hours and at login. Safe to run
# by hand. Prints one line per run and never prints a token.
#
#   __az_login_keepalive.sh               # refresh the default tenant
#   AZ_KEEPALIVE_TENANT=<id> __az_login_keepalive.sh
#
# Exit 0 on success or when offline (the next run retries). Exit 1 when the
# login is already gone or az fails for another reason, so the unit shows failed.
set -eo pipefail

TENANT="${AZ_KEEPALIVE_TENANT:-f1e389fd-172f-4426-9f75-88ebdaffac4a}"
AZ_BIN="${AZ_BIN:-az}"
PROBE_HOST="${AZ_KEEPALIVE_PROBE_HOST:-login.microsoftonline.com}"
AZ_TIMEOUT="${AZ_KEEPALIVE_TIMEOUT:-120}"

# say prints the run's single log line.
say() { printf '%s\n' "$*"; }

# first_error_line picks the first meaningful line of az's stderr, trimmed, with
# anything shaped like a JWT removed in case an error ever echoes one.
first_error_line() {
	sed -E 's/eyJ[A-Za-z0-9._-]+/[redacted]/g' <<<"$1" |
		grep -v -e '^[[:space:]]*$' | head -n 1 | cut -c1-200
}

main() {
	local out err rc code err_file

	if ! command -v "$AZ_BIN" >/dev/null 2>&1; then
		say "skip: az not found on PATH"
		return 0
	fi
	if ! getent hosts "$PROBE_HOST" >/dev/null 2>&1; then
		say "skip: offline, cannot resolve $PROBE_HOST"
		return 0
	fi

	err_file="$(mktemp)"
	trap 'rm -f "$err_file"' EXIT
	rc=0
	out="$(timeout "$AZ_TIMEOUT" "$AZ_BIN" account get-access-token \
		--tenant "$TENANT" --query expiresOn -o tsv 2>"$err_file")" || rc=$?
	err="$(cat "$err_file")"

	if [[ $rc -eq 0 ]]; then
		say "ok: tenant $TENANT access token valid until ${out:-unknown}"
		return 0
	fi
	if [[ $rc -eq 124 ]]; then
		say "skip: az timed out after ${AZ_TIMEOUT}s, likely offline"
		return 0
	fi
	if grep -qiE 'Failed to establish a new connection|NewConnectionError|Name or service not known|Temporary failure in name resolution|Max retries exceeded|Connection (refused|reset|aborted)|Network is unreachable' <<<"$err"; then
		say "skip: offline, az could not reach Entra"
		return 0
	fi

	code="$(grep -oE 'AADSTS[0-9]+' <<<"$err" | head -n 1 || true)"
	if [[ -n $code ]] || grep -qiE 'az login|interaction_required|invalid_grant' <<<"$err"; then
		say "fail: login expired${code:+ ($code)}, run: az login --tenant $TENANT"
		return 1
	fi
	say "fail: az exit $rc: $(first_error_line "$err")"
	return 1
}

main "$@"
