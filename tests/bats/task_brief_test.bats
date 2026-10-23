#!/usr/bin/env bats

# Test suite for __task_brief.sh. `task` and `tmux` are stubbed; the real
# TaskWarrior database is never touched.

setup() {
    TEST_DIR="$(mktemp -d)"
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    SCRIPT="${REPO_ROOT}/scripts/__task_brief.sh"
    FIXTURES="${REPO_ROOT}/tests/fixtures/task_brief"
    export TEST_DIR SCRIPT FIXTURES

    cat > "${TEST_DIR}/task" << 'STUB'
#!/bin/bash
echo "$*" >> "${TEST_DIR}/task_calls"
case "$*" in
  *843f1111-aaaa*) echo '[{"uuid":"843f1111-aaaa-4bbb-8ccc-000000000001","status":"pending","description":"Grant Kai push on loft-sh/kine?","repo":"no-repo","annotations":[]}]' ;;
  *7deb2222-aaaa*) echo '[{"uuid":"7deb2222-aaaa-4bbb-8ccc-000000000002","status":"pending","description":"Get PR 8827 approved","repo":"loft-sh/vcluster-pro","linear_issue_id":"DEVOPS-1717","annotations":[]}]' ;;
  *7deb3333-aaaa*) echo '[{"uuid":"7deb3333-aaaa-4bbb-8ccc-000000000003","status":"pending","description":"Second 7deb task","repo":"no-repo","annotations":[]}]' ;;
  *35ad51ef*) cat << 'JSON'
[{"uuid":"35ad51ef-988d-4d3e-b0b3-312f557d3ba0","status":"pending","description":"PAM onboarding flags still off: track activation?","project":"flows","tags":["piotr","handoff"],"annotations":[{"entry":"20261022T090000Z","description":"second note"},{"entry":"20261021T090000Z","description":"first note: yes means open the tracking issue"}]}]
JSON
  ;;
  *7f81e678*) cat "${FIXTURES}/7f81-2026-10-23T0924Z.json" ;;
  *fc0f43be*) cat "${FIXTURES}/fc0f-2026-10-23T1115Z.json" ;;
  *status:pending*) cat << 'JSON'
[{"uuid":"843f1111-aaaa-4bbb-8ccc-000000000001","status":"pending","description":"Grant Kai push on loft-sh/kine?","repo":"no-repo"},
 {"uuid":"7deb2222-aaaa-4bbb-8ccc-000000000002","status":"pending","description":"Get PR 8827 approved","repo":"loft-sh/vcluster-pro","linear_issue_id":"DEVOPS-1717"},
 {"uuid":"7deb3333-aaaa-4bbb-8ccc-000000000003","status":"pending","description":"Second 7deb task","repo":"no-repo"},
 {"uuid":"35ad51ef-988d-4d3e-b0b3-312f557d3ba0","status":"pending","description":"PAM onboarding flags still off: track activation?","repo":"no-repo"}]
JSON
  ;;
  *) echo "[]" ;;
esac
STUB
    chmod +x "${TEST_DIR}/task"
    cat > "${TEST_DIR}/tmux" << 'STUB'
#!/bin/bash
echo "$*" >> "${TEST_DIR}/tmux_calls"
if [ "$1" = list-panes ]; then
  [ -n "${STUB_NO_GORDON:-}" ] || { echo "%1 task"; echo "%4 triage"; }
  exit 0
fi
echo "$*" > "${TEST_DIR}/tmux_args"
STUB
    chmod +x "${TEST_DIR}/tmux"
    # Stands in for nvim: consumes the brief and exits with STUB_NVIM_RC, the
    # code the real key maps produce (0 close, 10 Enter, 11 s).
    cat > "${TEST_DIR}/nvim" << 'STUB'
#!/bin/bash
cat > "${TEST_DIR}/nvim_stdin"
exit "${STUB_NVIM_RC:-0}"
STUB
    chmod +x "${TEST_DIR}/nvim"
    export TASK_BRIEF_NVIM_COMMAND="${TEST_DIR}/nvim"
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
    history=${output#*History, oldest first:}
    first=${history%%second note*}
    [[ "$first" == *"first note"* ]]
}

# Handoff 7f81 as it stood when Piotr asked "what this is?" (23 Oct 09:24Z) and
# "what's with 7f?" (09:34Z): the options sat in a long 22 Oct note and the
# reply in the next one. The lead now puts them above the history.
@test "the 7f81 brief leads with the latest note, the options and the reply" {
    TASK_BRIEF_WIDTH=400 run "$SCRIPT" 7f81e678
    [ "$status" -eq 0 ]
    lead=${output%%uuid:*}
    [[ "$lead" == *"Latest: 10-22 08:39Z Live check 10:40: infrastructure ruleset 10216949"*"A shrinks to one change"* ]]
    [[ "$lead" == *"Effect: A (recommended): add eng-merge-devops in PR mode to those two; unblocks Piotr everywhere. B: also add"* ]]
    [[ "$lead" == *"Reply: Reply 'A': Gordon hands you the PUT. 'B': also org rulesets."* ]]
    [[ "$lead" != *"Decided:"* ]]
    [[ "${output#*History, oldest first:}" == *"Step 2 of 'add us to bypass"* ]]
}

# Handoff fc0f after Piotr answered (11:12) and Gordon offered a narrower reading (11:14).
@test "an answered handoff leads with Piotr's answer and the newer offer" {
    TASK_BRIEF_WIDTH=400 run "$SCRIPT" fc0f43be
    [ "$status" -eq 0 ]
    lead=${output%%uuid:*}
    [[ "$lead" == *'Decided: 10-23 11:11Z Piotr 11:12: "fc0f c: yeah sure'* ]]
    [[ "$lead" == *'Reply: Offer to Piotr 11:14: reply "only fc0f" and Gordon returns'* ]]
    [[ "$lead" == *'Latest: 10-23 11:14Z His 11:13 "we shall see"'* ]]
    # The options were answered: they are history now, not the effect.
    [[ "$lead" != *"Effect:"* ]]
}

@test "a task with no notes prints no lead and no history header" {
    run "$SCRIPT" 843f1111-aaaa
    [ "$status" -eq 0 ]
    [[ "$output" != *"History"* ]]
    [[ "$output" != *"Latest:"* ]]
}

@test "a plain note shows as Latest above the history" {
    run "$SCRIPT" 35ad51ef
    lead=${output%%uuid:*}
    [[ "$lead" == *"Latest: 10-22 09:00Z second note"* ]]
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

# --actions: 4-hex handoff ref from the Alt-m board

@test "--actions opens a popup that runs the actions mode for the ref" {
    run "$SCRIPT" --actions ' 843f G'
    [ "$status" -eq 0 ]
    grep -q 'display-popup' "${TEST_DIR}/tmux_args"
    grep -q -- "--actions-run '843f'" "${TEST_DIR}/tmux_args"
}

@test "unique ref resolves, shows the brief and the key legend" {
    STUB_NVIM_RC=0 run "$SCRIPT" --actions-run 843f
    [ "$status" -eq 0 ]
    grep -q 'Grant Kai push' "${TEST_DIR}/nvim_stdin"
    grep -q '\[Enter\] unfurl' "${TEST_DIR}/nvim_stdin"
}

@test "ref resolution reads pending tasks with hooks off" {
    STUB_NVIM_RC=0 run "$SCRIPT" --actions-run 843f
    grep -q 'status:pending' "${TEST_DIR}/task_calls"
    grep -q 'rc.hooks=off' "${TEST_DIR}/task_calls"
    ! grep -Eq ' (modify|annotate|done|add|delete)' "${TEST_DIR}/task_calls"
}

@test "ref with no pending task says so and sends nothing" {
    run "$SCRIPT" --actions-run beef </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"no pending task matches beef"* ]]
    [ ! -f "${TEST_DIR}/nvim_stdin" ]
    ! grep -q send-keys "${TEST_DIR}/tmux_calls" 2>/dev/null
}

@test "ambiguous ref lists the matches and the pick opens that task" {
    STUB_NVIM_RC=0 run "$SCRIPT" --actions-run 7deb <<<"2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"matches 2 pending tasks"* ]]
    [[ "$output" == *"7deb2222"* ]]
    [[ "$output" == *"7deb3333"* ]]
    grep -q 'Second 7deb task' "${TEST_DIR}/nvim_stdin"
}

@test "ambiguous ref cancelled by another key opens nothing" {
    run "$SCRIPT" --actions-run 7deb <<<"x"
    [ "$status" -eq 0 ]
    [ ! -f "${TEST_DIR}/nvim_stdin" ]
}

@test "Enter sends the no-repo task token literally, without Enter" {
    STUB_NVIM_RC=10 run "$SCRIPT" --actions-run 843f
    [ "$status" -eq 0 ]
    line=$(grep send-keys "${TEST_DIR}/tmux_calls")
    [[ "$line" == 'send-keys -t %4 -l -- @"843f1111-aaaa-4bbb-8ccc-000000000001|-|no-repo|Grant Kai push on loft-sh/kine?"' ]]
    [ "$(grep -c send-keys "${TEST_DIR}/tmux_calls")" -eq 1 ]
    ! grep -Eq 'Enter|C-m' "${TEST_DIR}/tmux_calls"
}

@test "token for a Linear task carries the linear id and repo" {
    STUB_NVIM_RC=10 run "$SCRIPT" --actions-run 7deb <<<"1"
    line=$(grep send-keys "${TEST_DIR}/tmux_calls")
    [[ "$line" == 'send-keys -t %4 -l -- @"7deb2222-aaaa-4bbb-8ccc-000000000002|DEVOPS-1717|loft-sh/vcluster-pro|Get PR 8827 approved"' ]]
}

@test "s sends the spawn prefix, the token and a trailing space" {
    STUB_NVIM_RC=11 run "$SCRIPT" --actions-run 843f
    [ "$status" -eq 0 ]
    line=$(grep send-keys "${TEST_DIR}/tmux_calls")
    [[ "$line" == 'send-keys -t %4 -l -- /ops-spawn-agent @"843f1111-aaaa-4bbb-8ccc-000000000001|-|no-repo|Grant Kai push on loft-sh/kine?" ' ]]
    ! grep -Eq 'Enter|C-m' "${TEST_DIR}/tmux_calls"
}

@test "q or Esc sends nothing" {
    STUB_NVIM_RC=0 run "$SCRIPT" --actions-run 843f
    [ "$status" -eq 0 ]
    ! grep -q send-keys "${TEST_DIR}/tmux_calls"
}

@test "no Gordon pane fails with a short message and sends nothing" {
    STUB_NO_GORDON=1 STUB_NVIM_RC=10 run "$SCRIPT" --actions-run 843f </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"no Gordon pane"* ]]
    ! grep -q send-keys "${TEST_DIR}/tmux_calls"
}

@test "Gordon pane is looked up by @agent_name" {
    STUB_NVIM_RC=10 run "$SCRIPT" --actions-run 843f
    grep -q "list-panes -a -F #{pane_id} #{@agent_name}" "${TEST_DIR}/tmux_calls"
}

@test "a full uuid opens the actions view regardless of status" {
    STUB_NVIM_RC=10 run "$SCRIPT" --actions-run 843f1111-aaaa-4bbb-8ccc-000000000001
    [ "$status" -eq 0 ]
    ! grep -q 'status:pending' "${TEST_DIR}/task_calls"
    grep -q 'send-keys -t %4 -l -- @"843f1111-aaaa' "${TEST_DIR}/tmux_calls"
}

@test "d marks the task done with hooks on and sends nothing" {
    STUB_NVIM_RC=12 run "$SCRIPT" --actions-run 843f
    [ "$status" -eq 0 ]
    line=$(grep ' done' "${TEST_DIR}/task_calls")
    [[ "$line" == *"843f1111-aaaa-4bbb-8ccc-000000000001 done" ]]
    [[ "$line" != *"rc.hooks=off"* ]]
    ! grep -q send-keys "${TEST_DIR}/tmux_calls"
}

@test "the legend names the d key" {
    STUB_NVIM_RC=0 run "$SCRIPT" --actions-run 843f
    grep -q '\[d\] done' "${TEST_DIR}/nvim_stdin"
}
