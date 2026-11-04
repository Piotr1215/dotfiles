#!/usr/bin/env bats

# __create_linear_issue.sh (taskwarrior-tui shortcut 8) and its DOC twin file a
# Linear issue from a task. Piotr, 26 Oct 2026: new issues carry no assignee
# unless he names one, and use the team's Triage state. Mock curl
# records every GraphQL body; mock task records every call.

setup() {
  SCRIPTS="${BATS_TEST_DIRNAME}/../../scripts"
  BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$BIN"
  export CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  export TASK_LOG="${BATS_TEST_TMPDIR}/task.log"
  : > "$CURL_LOG"
  : > "$TASK_LOG"
  export LINEAR_API_KEY=test-key
  export LINEAR_DEVOPS_TEAM_ID=team-devops
  export LINEAR_DOCS_TEAM_ID=team-docs
  export LOOKUP_REPLY='{"data":{"team":{"id":"team-devops","states":{"nodes":[{"id":"triage-devops","name":"Triage"}],"pageInfo":{"hasNextPage":false}}}}}'

  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  if [ "$1" = "--data" ]; then body="$2"; printf '%s\n' "$2" | jq -c . >> "$CURL_LOG"; shift; fi
  shift
done
if [[ "$body" == *TeamStates* ]]; then
  [ "${LOOKUP_FAIL:-0}" = 0 ] || exit 22
  printf '%s' "$LOOKUP_REPLY"
else
  printf '%s' "$CURL_REPLY"
fi
EOF
  cat > "$BIN/task" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TASK_LOG"
case "$*" in
  *"_get task-uuid.repo") printf '%s' "${TASK_REPO:-}" ;;
  *" export") if [[ -n "$TASK_EXPORT" ]]; then printf '%s' "$TASK_EXPORT"; else printf '%s' '[{"description":"fix the thing"}]'; fi ;;
esac
EOF
  chmod +x "$BIN/curl" "$BIN/task"
  export PATH="$BIN:$PATH"
}

reply_for() {
  printf '{"data":{"issueCreate":{"success":true,"issue":{"id":"i1","title":"fix the thing","url":"https://linear.app/loft/issue/%s-1800/fix-the-thing","number":1800}}}}' "$1"
}

@test "DEVOPS creation sends Triage and leaves the assignee unset" {
  export CURL_REPLY="$(reply_for DEVOPS)"
  run "$SCRIPTS/__create_linear_issue.sh" task-uuid
  [ "$status" -eq 0 ]
  [ "$(jq -s 'length' "$CURL_LOG")" = 2 ]
  [ "$(sed -n '2p' "$CURL_LOG" | jq -r '.query | test("assignee|viewer")')" = false ]
  [ "$(sed -n '2p' "$CURL_LOG" | jq -r '.variables.state')" = triage-devops ]
  [ "$(sed -n '2p' "$CURL_LOG" | jq -r '.query | contains("stateId: $state")')" = true ]
  [ "$(sed -n '2p' "$CURL_LOG" | jq -r '.variables.team')" = team-devops ]
  grep -Fx 'task-uuid modify linear_issue_id:DEVOPS-1800' "$TASK_LOG"
  grep -Fx 'task-uuid annotate https://linear.app/loft/issue/DEVOPS-1800/fix-the-thing' "$TASK_LOG"
}

@test "DOC creation sends its own Triage and links the task" {
  export LOOKUP_REPLY='{"data":{"team":{"id":"team-docs","states":{"nodes":[{"id":"triage-docs","name":"Triage"}],"pageInfo":{"hasNextPage":false}}}}}'
  export CURL_REPLY="$(reply_for DOC)"
  run "$SCRIPTS/__create_linear_issue_docs.sh" task-uuid
  [ "$status" -eq 0 ]
  [ "$(sed -n '2p' "$CURL_LOG" | jq -r '.variables.state')" = triage-docs ]
  [ "$(sed -n '2p' "$CURL_LOG" | jq -r '.variables.team')" = team-docs ]
  [ "$(sed -n '2p' "$CURL_LOG" | jq -r '.query | test("assignee|viewer")')" = false ]
  grep -Fx 'task-uuid modify linear_issue_id:DOC-1800' "$TASK_LOG"
  grep -Fx 'task-uuid annotate https://linear.app/loft/issue/DOC-1800/fix-the-thing' "$TASK_LOG"
}

@test "both scripts fail before creation for missing, ambiguous, incomplete or failed lookup" {
  for script in __create_linear_issue.sh __create_linear_issue_docs.sh; do
    for reply in \
      '{"data":{"team":{"id":"team-devops","states":{"nodes":[],"pageInfo":{"hasNextPage":false}}}}}' \
      '{"data":{"team":{"id":"team-devops","states":{"nodes":[{"id":"a","name":"Triage"},{"id":"b","name":"Triage"}],"pageInfo":{"hasNextPage":false}}}}}' \
      '{"data":{"team":{"id":"team-devops","states":{"nodes":[{"id":"a","name":"Triage"}],"pageInfo":{"hasNextPage":true}}}}}' \
      '{"errors":[{"message":"failed"}]}' \
      'invalid'; do
      : > "$CURL_LOG"
      export LOOKUP_REPLY="$reply"
      if [ "$script" = __create_linear_issue_docs.sh ]; then export LINEAR_DOCS_TEAM_ID=team-devops; fi
      run "$SCRIPTS/$script" task-uuid
      [ "$status" -ne 0 ]
      [ "$(wc -l < "$CURL_LOG")" -eq 1 ]
      ! grep -q issueCreate "$CURL_LOG"
    done
    : > "$CURL_LOG"
    export LOOKUP_FAIL=1
    run "$SCRIPTS/$script" task-uuid
    [ "$status" -ne 0 ]
    ! grep -q issueCreate "$CURL_LOG"
    unset LOOKUP_FAIL
  done
}

@test "both scripts clear the no-repo marker when linking the task" {
  export TASK_REPO=no-repo
  export CURL_REPLY="$(reply_for DEVOPS)"
  export LINEAR_DOCS_TEAM_ID=team-devops
  for script in __create_linear_issue.sh __create_linear_issue_docs.sh; do
    : > "$TASK_LOG"
    run "$SCRIPTS/$script" task-uuid
    [ "$status" -eq 0 ]
    grep -E '^task-uuid modify linear_issue_id:(DEVOPS|DOC)-1800 repo:$' "$TASK_LOG"
  done
}

@test "handoff promotion includes annotations and uses DevOps Triage" {
  export TASK_EXPORT='[{"description":"fix the thing","annotations":[{"description":"what: capacity"},{"description":"brief: investigate"},{"description":"done-when: fixed"}]}]'
  export CURL_REPLY="$(reply_for DEVOPS)"
  run "$SCRIPTS/__tui_promote_handoff.sh" task-uuid
  [ "$status" -eq 0 ]
  [ "$(sed -n '2p' "$CURL_LOG" | jq -r '.variables.state')" = triage-devops ]
  [ "$(sed -n '2p' "$CURL_LOG" | jq -r '.variables.desc')" = $'what: capacity\n\nbrief: investigate\n\ndone-when: fixed' ]
}
@test "handoff promotion refuses a task without its brief" {
  run "$SCRIPTS/__tui_promote_handoff.sh" task-uuid
  [ "$status" -ne 0 ]; [ ! -s "$CURL_LOG" ]
}
