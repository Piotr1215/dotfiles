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
  *3b9d8a8c*) cat "${FIXTURES}/3b9d-2026-10-26.json" ;;
  *31c0f89e*) cat << 'JSON'
[{"uuid":"31c0f89e-0000-4000-8000-000000000004","status":"pending","description":"Muse Slack app for Tom: deny until vendor checks?","annotations":[
 {"entry":"20261026T090145Z","description":"brief: Tom asked to install Muse. What you decide: how to answer the request: https://loft-labs-inc.slack.com/archives/D0BM7HMDDQB/p1792954856792359"},
 {"entry":"20261026T100000Z","description":"What: Tom Brightbill asked to install an AI triage app across our Slack workspace."}]}]
JSON
  ;;
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
    cat > "${TEST_DIR}/handoffs" << 'STUB'
#!/bin/bash
printf '%s\n' "$*" > "${TEST_DIR}/editor_args"
printf '%s\n' "$HANDOFFS_NVIM" > "${TEST_DIR}/editor_nvim"
STUB
    cat > "${TEST_DIR}/tw" << 'STUB'
#!/bin/bash
printf '%s\n' "$*" > "${TEST_DIR}/tw_calls"
STUB
    chmod +x "${TEST_DIR}/handoffs" "${TEST_DIR}/tw"
    export TASK_BRIEF_NVIM_COMMAND="${TEST_DIR}/nvim"
    export TASK_BRIEF_HANDOFFS_COMMAND="${TEST_DIR}/handoffs"
    export TASK_BRIEF_TW_COMMAND="${TEST_DIR}/tw"
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

# The what: note. On 26 Oct Piotr picked 3b9d with the @task picker and asked
# "what is this?" again: its notes were a log with no plain sentence saying
# what the task was.

@test "the newest what: note prints right under the title" {
    TASK_BRIEF_WIDTH=400 run "$SCRIPT" 3b9d8a8c
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "cap Anthropic spend before AI backports go live" ]
    [[ "${lines[1]}" == "What: Caue's GitHub Action resolves backport conflicts with Claude"*"is yours." ]]
    [[ "$output" != *"What: an older what line"* ]]
}

@test "a what: note never becomes the Latest line" {
    TASK_BRIEF_WIDTH=400 run "$SCRIPT" 3b9d8a8c
    lead=${output%%uuid:*}
    [[ "$lead" == *"Latest: 10-26 08:38Z pr merged: github-actions#329"* ]]
    [[ "$lead" != *"Latest: 10-26 10:00Z"* ]]
}

@test "a task with no what: note prints no What line" {
    run "$SCRIPT" 35ad51ef
    [[ "$output" != *"What:"* ]]
}

@test "--card prints ref, title, What, the step sentence and the other URLs" {
    run "$SCRIPT" --card '@"3b9d8a8c-8b20-4c8a-be3e-53be97a5e53e|-|no-repo|cap"'
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 4 ]
    [ "${lines[0]}" = "3b9d  cap Anthropic spend before AI backports go live" ]
    [[ "${lines[1]}" == "What: Caue's GitHub Action resolves"* ]]
    [ "${lines[2]}" = "Your step: set or confirm the cap in the Anthropic console: https://console.anthropic.com/settings/limits ." ]
    [ "${lines[3]}" = "https://github.com/loft-sh/github-actions/pull/330" ]
}

@test "--card takes a What you decide sentence and a capitalised What: note" {
    run "$SCRIPT" --card 31c0f89e
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "What: Tom Brightbill asked to install an AI triage app across our Slack workspace." ]
    [ "${lines[2]}" = "What you decide: how to answer the request: https://loft-labs-inc.slack.com/archives/D0BM7HMDDQB/p1792954856792359" ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "--card exits 3 with no output for a task without a what: note" {
    run "$SCRIPT" --card 35ad51ef
    [ "$status" -eq 3 ]
    [ -z "$output" ]
}

@test "--card on an unknown task fails" {
    run "$SCRIPT" --card deadbeef
    [ "$status" -eq 1 ]
}

@test "--card is read only" {
    run "$SCRIPT" --card 3b9d8a8c
    grep -q 'rc.hooks=off' "${TEST_DIR}/task_calls"
    ! grep -Eq ' (modify|annotate|done|add|delete)' "${TEST_DIR}/task_calls"
}
