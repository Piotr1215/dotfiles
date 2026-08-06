#!/usr/bin/env bats

# Test suite for __slack_open.sh
#
# Every test stubs the opener, so nothing here can reach the real Slack app or a
# browser: the script is exercised through SLACK_OPEN_OPENER, which exists for
# exactly this reason.

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR

    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="${REPO_ROOT}/scripts/__slack_open.sh"
    export SCRIPT

    cat > "${TEST_DIR}/opener" << 'EOF'
#!/bin/bash
echo "$*" > "${TEST_DIR}/opened"
EOF
    chmod +x "${TEST_DIR}/opener"
    export SLACK_OPEN_OPENER="${TEST_DIR}/opener"

    # Point the team map and the Slack state at empty test locations so a real
    # ~/.config or a real Slack install can never change a result.
    export SLACK_OPEN_TEAMS_CONFIG="${TEST_DIR}/teams"
    export SLACK_STATE_DIR="${TEST_DIR}/slack-state"
    unset SLACK_TEAM_ID
}

teardown() {
    rm -rf "$TEST_DIR"
}

opened() {
    cat "${TEST_DIR}/opened" 2>/dev/null
}

@test "converts a message permalink into a slack:// deep link" {
    export SLACK_TEAM_ID="T024313FSQZ"

    run "$SCRIPT" "https://loft-labs-inc.slack.com/archives/C0364G7S4UR/p1785876243182299"
    [ "$status" -eq 0 ]
    [ "$(opened)" = "slack://channel?team=T024313FSQZ&id=C0364G7S4UR&message=1785876243.182299" ]
}

@test "splits the permalink timestamp six digits from the right" {
    # p1785876243182299 is 1785876243.182299; the last six digits are always
    # the microseconds.
    export SLACK_TEAM_ID="T1"

    run "$SCRIPT" "https://ws.slack.com/archives/C1/p1773732437844199"
    [ "$status" -eq 0 ]
    echo "$(opened)" | grep -q "message=1773732437.844199"
}

@test "carries thread_ts through so a reply opens its thread" {
    export SLACK_TEAM_ID="T1"

    run "$SCRIPT" "https://ws.slack.com/archives/C1/p1785876243182299?thread_ts=1785876243.182299&cid=C1"
    [ "$status" -eq 0 ]
    echo "$(opened)" | grep -q "thread_ts=1785876243.182299"
}

@test "omits thread_ts when the permalink carries none" {
    export SLACK_TEAM_ID="T1"

    run "$SCRIPT" "https://ws.slack.com/archives/C1/p1785876243182299?cid=C1"
    [ "$status" -eq 0 ]
    ! echo "$(opened)" | grep -q "thread_ts"
}

@test "reads the team id from the teams config when the env var is unset" {
    echo "# comment line" > "${TEST_DIR}/teams"
    echo "other-workspace TOTHER" >> "${TEST_DIR}/teams"
    echo "loft-labs-inc T024313FSQZ" >> "${TEST_DIR}/teams"

    run "$SCRIPT" "https://loft-labs-inc.slack.com/archives/C1/p1785876243182299"
    [ "$status" -eq 0 ]
    echo "$(opened)" | grep -q "team=T024313FSQZ"
}

@test "SLACK_TEAM_ID wins over the teams config" {
    echo "loft-labs-inc TFROMFILE" > "${TEST_DIR}/teams"
    export SLACK_TEAM_ID="TFROMENV"

    run "$SCRIPT" "https://loft-labs-inc.slack.com/archives/C1/p1785876243182299"
    [ "$status" -eq 0 ]
    echo "$(opened)" | grep -q "team=TFROMENV"
}

@test "falls back to the browser when no team id is known" {
    # The team id is the one value a permalink cannot supply. Not knowing it
    # must degrade to the original link, never to a broken deep link.
    run "$SCRIPT" "https://unknown-ws.slack.com/archives/C1/p1785876243182299"
    [ "$status" -eq 0 ]
    [ "$(opened)" = "https://unknown-ws.slack.com/archives/C1/p1785876243182299" ]
}

@test "the fallback names the remedy, not just the problem" {
    run "$SCRIPT" "https://unknown-ws.slack.com/archives/C1/p1785876243182299"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q -- "--detect"
    echo "$output" | grep -q "unknown-ws <TEAM_ID>"
}

@test "hands a non-permalink slack url to the browser unchanged" {
    export SLACK_TEAM_ID="T1"

    run "$SCRIPT" "https://loft-labs-inc.slack.com/canvas/C1234"
    [ "$status" -eq 0 ]
    [ "$(opened)" = "https://loft-labs-inc.slack.com/canvas/C1234" ]
}

@test "exits non-zero with usage when given no argument" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Usage:"
}
