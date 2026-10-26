#!/usr/bin/env bats

# __create_linear_issue.sh (taskwarrior-tui shortcut 8) and its DOC twin file a
# Linear issue from a task. Piotr, 26 Oct 2026: new issues carry no assignee
# unless he names one, and stay in the team's default state (Triage). Mock curl
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

  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  if [ "$1" = "--data" ]; then printf '%s\n' "$2" >> "$CURL_LOG"; shift; fi
  shift
done
printf '%s' "$CURL_REPLY"
EOF
  cat > "$BIN/task" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TASK_LOG"
case "$*" in
  *" export") printf '[{"description":"fix the thing"}]' ;;
esac
EOF
  chmod +x "$BIN/curl" "$BIN/task"
  export PATH="$BIN:$PATH"
}

reply_for() {
  printf '{"data":{"issueCreate":{"success":true,"issue":{"id":"i1","title":"fix the thing","url":"https://linear.app/loft/issue/%s-1800/fix-the-thing","number":1800}}}}' "$1"
}

@test "a DEVOPS issue is created with no assignee and no state" {
  export CURL_REPLY="$(reply_for DEVOPS)"
  run "$SCRIPTS/__create_linear_issue.sh" task-uuid
  [ "$status" -eq 0 ]
  [ "$(jq -s 'length' "$CURL_LOG")" = 1 ]
  [ "$(jq -r '.query | test("assignee|stateId|viewer")' "$CURL_LOG")" = false ]
  [ "$(jq -c '.variables | keys' "$CURL_LOG")" = '["desc","team","title"]' ]
  [ "$(jq -r '.variables.team' "$CURL_LOG")" = team-devops ]
}

@test "a DEVOPS issue still links its id back to the task" {
  export CURL_REPLY="$(reply_for DEVOPS)"
  run "$SCRIPTS/__create_linear_issue.sh" task-uuid
  [ "$status" -eq 0 ]
  grep -Fx 'task-uuid modify linear_issue_id:DEVOPS-1800' "$TASK_LOG"
  grep -Fx 'task-uuid annotate https://linear.app/loft/issue/DEVOPS-1800/fix-the-thing' "$TASK_LOG"
}

@test "a DOC issue is created with no assignee and no state" {
  export CURL_REPLY="$(reply_for DOC)"
  run "$SCRIPTS/__create_linear_issue_docs.sh" task-uuid
  [ "$status" -eq 0 ]
  [ "$(jq -s 'length' "$CURL_LOG")" = 1 ]
  [ "$(jq -r '.query | test("assignee|stateId|viewer")' "$CURL_LOG")" = false ]
  [ "$(jq -c '.variables | keys' "$CURL_LOG")" = '["desc","team","title"]' ]
  [ "$(jq -r '.variables.team' "$CURL_LOG")" = team-docs ]
  grep -Fx 'task-uuid modify linear_issue_id:DOC-1800' "$TASK_LOG"
}
