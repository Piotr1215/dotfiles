#!/usr/bin/env bats
# __az_login_keepalive.sh runs from az-login-keepalive.timer. It must print one
# line per run, stay green when offline, fail with the remedy when the login is
# already gone, and never print a token.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__az_login_keepalive.sh"
    T="$(mktemp -d)"
    mkdir -p "$T/bin"
    # getent stand-in: resolves unless OFFLINE=1.
    cat >"$T/bin/getent" <<'EOF'
#!/usr/bin/env bash
[[ ${OFFLINE:-0} == 1 ]] && exit 2
echo "127.0.0.1 $2"
EOF
    # az stand-in: records its args, prints AZ_STDOUT and AZ_STDERR, exits AZ_RC.
    cat >"$T/bin/az" <<EOF
#!/usr/bin/env bash
echo "\$*" >"$T/az-args"
[[ -n \${AZ_STDOUT:-} ]] && printf '%s\n' "\$AZ_STDOUT"
[[ -n \${AZ_STDERR:-} ]] && printf '%s\n' "\$AZ_STDERR" >&2
exit "\${AZ_RC:-0}"
EOF
    chmod +x "$T/bin/getent" "$T/bin/az"
    export PATH="$T/bin:$PATH"
    unset AZ_KEEPALIVE_TENANT AZ_BIN OFFLINE AZ_STDOUT AZ_STDERR AZ_RC
}

teardown() {
    rm -rf "$T"
}

@test "success logs one ok line with the expiry and no token" {
    export AZ_STDOUT="2026-11-25 01:35:29.000000"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == "ok: tenant f1e389fd-172f-4426-9f75-88ebdaffac4a access token valid until 2026-11-25 01:35:29.000000" ]]
}

@test "asks az only for the expiry of the given tenant" {
    export AZ_KEEPALIVE_TENANT=tenant-x AZ_STDOUT=x
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$(cat "$T/az-args")" == "account get-access-token --tenant tenant-x --query expiresOn -o tsv" ]]
}

@test "offline by DNS skips quietly without calling az" {
    export OFFLINE=1
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == "skip: offline"* ]]
    [ ! -e "$T/az-args" ]
}

@test "a connection error from az skips quietly" {
    export AZ_RC=1 AZ_STDERR="ERROR: HTTPSConnectionPool(host='login.microsoftonline.com', port=443): Max retries exceeded with url: /organizations"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == "skip: offline, az could not reach Entra" ]]
}

@test "an az timeout skips quietly" {
    export AZ_KEEPALIVE_TIMEOUT=1
    cat >"$T/bin/az" <<'EOF'
#!/usr/bin/env bash
sleep 5
EOF
    chmod +x "$T/bin/az"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == "skip: az timed out after 1s, likely offline" ]]
}

@test "an expired refresh token fails with the code and the remedy" {
    export AZ_RC=1 AZ_STDERR=$'ERROR: AADSTS700082: The refresh token has expired due to inactivity.\nInteractive authentication is needed. Please run:\naz login'
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == "fail: login expired (AADSTS700082), run: az login --tenant f1e389fd-172f-4426-9f75-88ebdaffac4a" ]]
}

@test "any other az error fails with its first line, redacting a JWT" {
    export AZ_RC=2 AZ_STDERR=$'\nERROR: unexpected eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ4In0.sig here\nmore'
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == "fail: az exit 2: ERROR: unexpected [redacted] here" ]]
}

@test "missing az skips quietly" {
    export AZ_BIN=/nonexistent/az
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == "skip: az not found on PATH" ]]
}
