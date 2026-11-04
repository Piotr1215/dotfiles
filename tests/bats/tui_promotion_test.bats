#!/usr/bin/env bats
setup() {
  script="${BATS_TEST_DIRNAME}/../../scripts/__tui_promote_handoff.sh"
  bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"; export PATH="$bin:$PATH"
  export LOG="$BATS_TEST_TMPDIR/curl.log" TASK_LOG="$BATS_TEST_TMPDIR/task.log" REMOTE="$BATS_TEST_TMPDIR/remote" LINK="$BATS_TEST_TMPDIR/link"
  export LINEAR_API_KEY=test LINEAR_DEVOPS_TEAM_ID=team-devops
  uuid=12345678-1234-4234-8234-123456789abc
  cat > "$bin/task" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TASK_LOG"
if [[ "$*" == *export ]]; then
  link=''; [[ ! -f "$LINK" ]] || link=$(cat "$LINK")
  jq -n --arg link "$link" '[{description:"fix it",repo:"no-repo",linear_issue_id:$link,annotations:[{description:"what: capacity"},{description:"brief: investigate"},{description:"done-when: fixed"}]}]'
elif [[ "$*" == *modify* ]]; then
  [[ "${FAIL_ATTACH:-0}" == 0 ]] || exit 1
  echo DEVOPS-1800 > "$LINK"
fi
MOCK
  cat > "$bin/curl" <<'MOCK'
#!/usr/bin/env bash
while (($#)); do if [[ "$1" == --data ]]; then body=$2; shift; fi; shift; done
printf '%s\n' "$body" | jq -c . >> "$LOG"
if [[ "$body" == *TeamStates* ]]; then
  echo '{"data":{"team":{"id":"team-devops","states":{"nodes":[{"id":"triage","name":"Triage"}],"pageInfo":{"hasNextPage":false}}}}}'
elif [[ "$body" == *IssueCreate* ]]; then
  id=$(jq -r '.variables.id' <<< "$body")
  if [[ "${CREATE_ERROR:-0}" == 1 || -f "$REMOTE" ]]; then echo '{"errors":[{"message":"failed"}]}'; exit; fi
  echo "$id" > "$REMOTE"
  jq -n --arg id "$id" '{data:{issueCreate:{success:true,issue:{id:$id,identifier:"DEVOPS-1800",url:"https://linear.app/loft/issue/DEVOPS-1800",team:{id:"team-devops"}}}}}'
else
  if [[ -f "$REMOTE" ]]; then id=$(cat "$REMOTE"); jq -n --arg id "$id" '{data:{issue:{id:$id,identifier:"DEVOPS-1800",url:"https://linear.app/loft/issue/DEVOPS-1800",team:{id:"team-devops"}}}}'; else echo '{"errors":[{"message":"not found"}]}'; fi
fi
MOCK
  chmod +x "$bin/task" "$bin/curl"
}
@test "promotion creates once and repeat with linked issue is a no-op" {
  run "$script" "$uuid"; [ "$status" -eq 0 ]
  [ "$(wc -l < "$LOG")" -eq 2 ]
  [ "$(sed -n '2p' "$LOG" | jq -r '.variables.desc')" = $'what: capacity\n\nbrief: investigate\n\ndone-when: fixed' ]
  [ "$(sed -n '2p' "$LOG" | jq -r '.variables.state')" = triage ]
  run "$script" "$uuid"; [ "$status" -eq 0 ]; [ "$(wc -l < "$LOG")" -eq 2 ]
}
@test "graphql errors do not attach an issue" {
  export CREATE_ERROR=1
  run "$script" "$uuid"; [ "$status" -ne 0 ]; [ "$(wc -l < "$LOG")" -eq 3 ]; [ ! -f "$LINK" ]; [ ! -f "$REMOTE" ]
}
@test "failed local attach retries with same issue id and recovers remote issue" {
  export FAIL_ATTACH=1
  run "$script" "$uuid"; [ "$status" -ne 0 ]; [ "$(wc -l < "$LOG")" -eq 2 ]; [ -f "$REMOTE" ]; [ ! -f "$LINK" ]
  unset FAIL_ATTACH
  run "$script" "$uuid"; [ "$status" -eq 0 ]; [ "$(wc -l < "$LOG")" -eq 5 ]; [ -f "$LINK" ]
  [ "$(sed -n '2p' "$LOG" | jq -r '.variables.id')" = "$(sed -n '4p' "$LOG" | jq -r '.variables.id')" ]
  [ "$(grep -c IssueCreate "$LOG")" -eq 2 ]; [ "$(grep -c ExistingIssue "$LOG")" -eq 1 ]
}
