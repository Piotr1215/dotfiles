#!/usr/bin/env bats

setup() {
    set_file="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/.config/value-sets/slack"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export SLACK_CHANNELS_CACHE="$BATS_TEST_TMPDIR/cache/slack-channels.txt"
    export SLACK_CHANNELS_TOKEN_CMD="echo xoxp-test"
    export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
}

# curl stub: logs the header it got on stdin and its args, then answers page 1
# (with a cursor) or page 2, or fails when CURL_MODE says so.
stub_curl() {
    cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
{ cat; printf 'ARGS %s\n' "$*"; } >> "$CURL_LOG"
case "${CURL_MODE:-ok}" in
    down) exit 7 ;;
    notok) echo '{"ok":false,"error":"invalid_auth"}'; exit 0 ;;
esac
if [[ "$*" == *"cursor=next1"* ]]; then
    echo '{"ok":true,"channels":[{"name":"alpha"}],"response_metadata":{"next_cursor":""}}'
else
    echo '{"ok":true,"channels":[{"name":"zeta"},{"name":"private-ops"}],"response_metadata":{"next_cursor":"next1"}}'
fi
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
}

@test "slack value set lists every page of the user's channels, sorted, and caches them" {
    stub_curl
    run "$set_file"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '#alpha\n#private-ops\n#zeta')" ]
    [ "$(cat "$SLACK_CHANNELS_CACHE")" = "$output" ]
    grep -q 'users.conversations' "$CURL_LOG"
    grep -q 'types=public_channel,private_channel' "$CURL_LOG"
    grep -q 'exclude_archived=true' "$CURL_LOG"
}

@test "slack value set sends the token on stdin, never in curl's arguments" {
    stub_curl
    run "$set_file"
    [ "$status" -eq 0 ]
    grep -qx 'Authorization: Bearer xoxp-test' "$CURL_LOG"
    ! grep '^ARGS' "$CURL_LOG" | grep -q 'xoxp-test'
}

@test "slack value set serves the last good list when Slack is unreachable" {
    stub_curl
    mkdir -p "$(dirname "$SLACK_CHANNELS_CACHE")"
    printf '#cached\n' > "$SLACK_CHANNELS_CACHE"
    CURL_MODE=down run "$set_file"
    [ "$status" -eq 0 ]
    [ "$output" = "#cached" ]
}

@test "slack value set keeps the cache when Slack answers not ok" {
    stub_curl
    mkdir -p "$(dirname "$SLACK_CHANNELS_CACHE")"
    printf '#cached\n' > "$SLACK_CHANNELS_CACHE"
    CURL_MODE=notok run "$set_file"
    [ "$status" -eq 0 ]
    [ "$output" = "#cached" ]
    [ "$(cat "$SLACK_CHANNELS_CACHE")" = "#cached" ]
}

@test "slack value set skips Slack and serves the cache when no token is readable" {
    stub_curl
    mkdir -p "$(dirname "$SLACK_CHANNELS_CACHE")"
    printf '#cached\n' > "$SLACK_CHANNELS_CACHE"
    SLACK_CHANNELS_TOKEN_CMD="false" run "$set_file"
    [ "$status" -eq 0 ]
    [ "$output" = "#cached" ]
    [ ! -e "$CURL_LOG" ]
}

@test "slack value set prints nothing and succeeds with no token and no cache" {
    stub_curl
    SLACK_CHANNELS_TOKEN_CMD="false" run "$set_file"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
