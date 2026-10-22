#!/usr/bin/env bats

# Test suite for __task_brief.sh. `task` and `tmux` are stubbed; the real
# TaskWarrior database is never touched.

setup() {
    TEST_DIR="$(mktemp -d)"
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    SCRIPT="${REPO_ROOT}/scripts/__task_brief.sh"
    export TEST_DIR SCRIPT

    cat > "${TEST_DIR}/task" << 'STUB'
#!/bin/bash
echo "$*" >> "${TEST_DIR}/task_calls"
case "$*" in
  *35ad51ef*) cat << 'JSON'
[{"uuid":"35ad51ef-988d-4d3e-b0b3-312f557d3ba0","status":"pending","description":"PAM onboarding flags still off: track activation?","project":"flows","tags":["piotr","handoff"],"annotations":[{"entry":"20261022T090000Z","description":"second note"},{"entry":"20261021T090000Z","description":"first note: yes means open the tracking issue"}]}]
JSON
  ;;
  *) echo "[]" ;;
esac
STUB
    chmod +x "${TEST_DIR}/task"
    cat > "${TEST_DIR}/tmux" << 'STUB'
#!/bin/bash
echo "$*" > "${TEST_DIR}/tmux_args"
STUB
    chmod +x "${TEST_DIR}/tmux"
    export TASK_BRIEF_TASK_COMMAND="${TEST_DIR}/task"
    export TASK_BRIEF_TMUX_COMMAND="${TEST_DIR}/tmux"
}

teardown() {
    rm -rf "${TEST_DIR}"
}

@test "prints description, tags and annotations oldest first" {
    run "$SCRIPT" 35ad51ef
    [ "$status" -eq 0 ]
    [[ "$output" == *"PAM onboarding flags still off"* ]]
    [[ "$output" == *"tags:    piotr handoff"* ]]
    first=${output%%second note*}
    [[ "$first" == *"first note"* ]]
}

@test "accepts a full picker token" {
    run "$SCRIPT" '@"35ad51ef-988d-4d3e-b0b3-312f557d3ba0|-|flows|PAM"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"first note"* ]]
}

@test "export is read only and ignores context" {
    run "$SCRIPT" 35ad51ef
    grep -q 'rc.context=none' "${TEST_DIR}/task_calls"
    grep -q 'rc.hooks=off' "${TEST_DIR}/task_calls"
    grep -q ' export' "${TEST_DIR}/task_calls"
    ! grep -Eq ' (modify|annotate|done|add|delete)' "${TEST_DIR}/task_calls"
}

@test "wraps to TASK_BRIEF_WIDTH" {
    TASK_BRIEF_WIDTH=30 run "$SCRIPT" 35ad51ef
    while IFS= read -r line; do [ "${#line}" -le 30 ]; done <<<"$output"
}

@test "unknown task fails" {
    run "$SCRIPT" deadbeef
    [ "$status" -eq 1 ]
    [[ "$output" == *"no task matches"* ]]
}

@test "non-reference fails" {
    run "$SCRIPT" "zzz"
    [ "$status" -eq 2 ]
}

@test "--popup opens a tmux popup running the brief" {
    run "$SCRIPT" --popup '@"35ad51ef-988d-4d3e-b0b3-312f557d3ba0|-|x|y"'
    [ "$status" -eq 0 ]
    grep -q 'display-popup' "${TEST_DIR}/tmux_args"
    grep -q '35ad51ef-988d-4d3e-b0b3-312f557d3ba0' "${TEST_DIR}/tmux_args"
}
