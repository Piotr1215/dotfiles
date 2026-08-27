#!/usr/bin/env bats

# Test suite for __taskopen_url_open.sh
#
# Both the opener and the layout script are stubbed, so nothing here can reach a
# real browser or move a real window: TASKOPEN_URL_OPENER and
# TASKOPEN_URL_LAYOUT_SCRIPT exist for exactly this reason.

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR

    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="${REPO_ROOT}/scripts/__taskopen_url_open.sh"
    export SCRIPT

    cat > "${TEST_DIR}/opener" << 'EOF'
#!/bin/bash
echo "$*" > "${TEST_DIR}/opened"
EOF
    chmod +x "${TEST_DIR}/opener"
    export TASKOPEN_URL_OPENER="${TEST_DIR}/opener"

    cat > "${TEST_DIR}/layouts" << 'EOF'
#!/bin/bash
echo "$*" > "${TEST_DIR}/tiled"
EOF
    chmod +x "${TEST_DIR}/layouts"
    export TASKOPEN_URL_LAYOUT_SCRIPT="${TEST_DIR}/layouts"

    # Run the opener synchronously; a detached stub would race the assertions.
    export TASKOPEN_URL_NO_DETACH=1
    # The production delay exists to let the browser map its window. Nothing
    # here waits on a real window, so keep the suite fast.
    export TASKOPEN_URL_LAYOUT_DELAY=0
}

teardown() {
    rm -rf "$TEST_DIR"
}

opened() {
    cat "${TEST_DIR}/opened" 2>/dev/null
}

tiled() {
    cat "${TEST_DIR}/tiled" 2>/dev/null
}

@test "opens the url it is given" {
    run "$SCRIPT" "https://github.com/loft-sh/vcluster/pull/1"
    [ "$status" -eq 0 ]
    [ "$(opened)" = "https://github.com/loft-sh/vcluster/pull/1" ]
}

@test "tiles browser and terminal after opening" {
    run "$SCRIPT" "https://example.com"
    [ "$status" -eq 0 ]
    [ "$(tiled)" = "2" ]
}

@test "TASKOPEN_URL_LAYOUT selects the layout" {
    export TASKOPEN_URL_LAYOUT=18

    run "$SCRIPT" "https://example.com"
    [ "$status" -eq 0 ]
    [ "$(tiled)" = "18" ]
}

@test "TASKOPEN_URL_LAYOUT=0 opens without tiling" {
    export TASKOPEN_URL_LAYOUT=0

    run "$SCRIPT" "https://example.com"
    [ "$status" -eq 0 ]
    [ "$(opened)" = "https://example.com" ]
    [ ! -f "${TEST_DIR}/tiled" ]
}

@test "a missing layout script does not fail the open" {
    export TASKOPEN_URL_LAYOUT_SCRIPT="${TEST_DIR}/nope"

    run "$SCRIPT" "https://example.com"
    [ "$status" -eq 0 ]
    [ "$(opened)" = "https://example.com" ]
}

@test "exits non-zero with usage when given no argument" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Usage:"
}
