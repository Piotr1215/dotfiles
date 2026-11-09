#!/usr/bin/env bats
setup() {
  script="${BATS_TEST_DIRNAME}/../../scripts/__tui_promote_handoff.sh"
  bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"; export PATH="$bin:$PATH"
  export LOG="$BATS_TEST_TMPDIR/curl.log" TASK_LOG="$BATS_TEST_TMPDIR/task.log" REMOTE="$BATS_TEST_TMPDIR/remote" LINK="$BATS_TEST_TMPDIR/link"
  export LINEAR_API_KEY=test LINEAR_DEVOPS_TEAM_ID=team-devops TASK_BRIEFS_DIR="$BATS_TEST_TMPDIR/briefs"
  uuid=12345678-1234-4234-8234-123456789abc
  cat > "$bin/task" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TASK_LOG"
if [[ "$*" == *export ]]; then
  link=''; [[ ! -f "$LINK" ]] || link=$(cat "$LINK")
  if [[ -n "${TASK_JSON:-}" ]]; then jq --arg link "$link" '.[0].linear_issue_id = $link' "$TASK_JSON"; else
  jq -n --arg link "$link" '[{description:"fix it",repo:"no-repo",linear_issue_id:$link,annotations:[{description:"what: capacity"},{description:"brief: investigate"},{description:"done-when: fixed"}]}]'; fi
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
  echo '{"data":{"team":{"id":"team-devops","states":{"nodes":[{"id":"triage","name":"Triage"}],"pageInfo":{"hasNextPage":false}}},"issueLabels":{"nodes":[{"id":"lbl-other","name":"security","team":{"id":"team-other"}},{"id":"lbl-sec","name":"security","team":{"id":"team-devops"}}]}}}'
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
  [ "$(sed -n '2p' "$LOG" | jq -r '.variables.desc')" = $'capacity\n\nDone when: fixed' ]
  [ "$(sed -n '2p' "$LOG" | jq -r '.variables.priority')" = 0 ]
  [ "$(sed -n '2p' "$LOG" | jq -c '.variables.labels')" = '[]' ]
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

# DEVOPS-1862 regression: the 0f54fdc8 handoff shape, rendered without any network call.
write_handoff() {
  mkdir -p "$BATS_TEST_TMPDIR/brief"
  cat > "$BATS_TEST_TMPDIR/brief/brief.md" <<'MD'
# Delete the firmus-jump-host droplet

## What

Pascal agreed in #security to retire firmus-jump-host. Deleting a server is yours to run.

## Brief

Your step: run the delete below. Thread: https://loft-labs-inc.slack.com/archives/C04LHJ0NZ55/p1794241270584869
`doctl compute droplet delete 578057490 --force`

## Done when

droplet gone
MD
  export TASK_JSON="$BATS_TEST_TMPDIR/task.json"
  jq -n --arg trace "$BATS_TEST_TMPDIR/brief/brief.md" --arg pri "${PRI-M}" '[{uuid:"0f54fdc8-c26e-4782-8081-75ee08865e81",description:"Delete the firmus-jump-host droplet: Pascal agreed to retire it, last host open for the kernel CVE",priority:$pri,tags:["piotr","work"],repo:"no-repo",annotations:[
    {entry:"20261109T163750Z",description:"done-when: manual droplet 578057490 no longer listed"},
    {entry:"20261109T163751Z",description:"what: Pascal agreed in #security to retire firmus-jump-host, the last DigitalOcean host still open for the kernel CVE. Nothing else depends on it. Deleting a server is yours to run."},
    {entry:"20261109T163752Z",description:("trace: " + $trace)},
    {entry:"20261109T163753Z",description:"brief-updated: handoff"},
    {entry:"20261109T163754Z",description:"cmd: doctl compute droplet list"},
    {entry:"20261109T163755Z",description:"cmd: doctl compute droplet delete 578057490 --force"},
    {entry:"20261109T163756Z",description:"link: https://github.com/loft-sh/infra/issues/7"},
    {entry:"20261109T163757Z",description:"proof: https://github.com/loft-sh/ignored/pull/1"}]}] | if $pri == "" then .[0].priority = null else . end' > "$TASK_JSON"
}
render() { python3 "${BATS_TEST_DIRNAME}/../../scripts/__tui_promote_render.py" < "$TASK_JSON"; }

@test "title is lowercased" {
  write_handoff
  [ "$(render | jq -r .title)" = "delete the firmus-jump-host droplet: pascal agreed to retire it, last host open for the kernel cve" ]
}
@test "description reads as an issue: neutral what, sources, newest cmd, done when" {
  write_handoff
  expected=$'Pascal agreed in #security to retire firmus-jump-host, the last DigitalOcean host still open for the kernel CVE. Nothing else depends on it.\n\nSources:\n- https://github.com/loft-sh/infra/issues/7\n- https://loft-labs-inc.slack.com/archives/C04LHJ0NZ55/p1794241270584869\n\nCommand:\n\n```sh\ndoctl compute droplet delete 578057490 --force\n```\n\nDone when: manual droplet 578057490 no longer listed'
  [ "$(render | jq -r .description)" = "$expected" ]
  ! render | jq -r .description | grep -qE 'yours to run|trace:|brief-updated|ignored/pull'
}
@test "priority maps H M L and none" {
  for pair in H:2 M:3 L:4 :0; do
    PRI=${pair%%:*} write_handoff
    [ "$(render | jq -r .priority)" = "${pair#*:}" ]
  done
}
@test "security handoff sends priority and the team's existing security label only" {
  write_handoff
  run "$script" "$uuid"; [ "$status" -eq 0 ]
  create=$(grep IssueCreate "$LOG")
  [ "$(jq -r '.variables.priority' <<< "$create")" = 3 ]
  [ "$(jq -c '.variables.labels' <<< "$create")" = '["lbl-sec"]' ]
  [ "$(jq -r '.variables.title' <<< "$create")" = "delete the firmus-jump-host droplet: pascal agreed to retire it, last host open for the kernel cve" ]
  ! grep -q -i 'labelCreate\|issueLabelCreate' "$LOG"
}
@test "no security mention means no label" {
  run "$script" "$uuid"; [ "$status" -eq 0 ]
  [ "$(grep IssueCreate "$LOG" | jq -c '.variables.labels')" = '[]' ]
}
