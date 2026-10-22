#!/usr/bin/env bats

# __spacelift_notifications.sh against a stub spacectl that serves a fixture,
# never the live Spacelift API. State and the event log live in a temp dir.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__spacelift_notifications.sh"
  WORK="$(mktemp -d)"
  export SPACELIFT_EVENTS_STATE="${WORK}/state"
  export SPACELIFT_EVENTS_LOG="${WORK}/notifications.log"
  export SPACELIFT_EVENTS_SPACECTL="${WORK}/spacectl"
  export SL_FIXTURE="${WORK}/answer.json"
  cat >"$SPACELIFT_EVENTS_SPACECTL" <<'EOF'
#!/usr/bin/env bash
[[ -e "${SL_FIXTURE}.fail" ]] && { echo "dial tcp: i/o timeout" >&2; exit 1; }
cat "$SL_FIXTURE"
EOF
  chmod +x "$SPACELIFT_EVENTS_SPACECTL"
  NOW="$(date +%s)"
  NODES=()
}

teardown() {
  rm -rf "$WORK"
}

# node <id> <count> <age seconds> <dismissed> <severity> <kind> <target> <title> <body>
node() {
  NODES+=("$(jq -nc --arg id "$1" --argjson n "$2" --argjson at "$((NOW - $3))" --argjson d "$4" \
    --arg sev "$5" --arg kind "$6" --arg target "$7" --arg title "$8" --arg body "$9" \
    '{node: {id: $id, occurrencesCount: $n, lastOccurrenceAt: $at, dismissed: $d, severity: $sev,
      groupingKey: $kind, target: $target, title: $title, body: $body}}')")
}

serve() {
  local edges
  edges="$(printf '%s\n' "${NODES[@]}" | jq -sc .)"
  [[ "${#NODES[@]}" -gt 0 ]] || edges='[]'
  jq -nc --argjson e "$edges" '{data: {searchNotifications: {edges: $e}}}' >"$SL_FIXTURE"
}

records() {
  if [[ -f "$SPACELIFT_EVENTS_LOG" ]]; then cat "$SPACELIFT_EVENTS_LOG"; fi
}

record_count() {
  records | grep -c . || true
}

@test "the first run records the last day and seeds older notifications" {
  node new1 1 600 false ERROR vcs-failure stack/sandbox-aws-account-gezzgx "Could not notify VCS" \
    "could not query GitHub API: POST https://api.github.com/repos/loft-sh/terraform-modules/check-runs: 500"
  node old1 1 $((3 * 86400)) false WARNING run-updated stack/old "Sandbox 'old' scheduled for deletion" "gone"
  serve

  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [ "$(record_count)" -eq 1 ]
  line="$(records)"
  [ "$(awk -F'\t' '{print NF}' <<<"$line")" -eq 4 ]
  [ "$(cut -f2,3 <<<"$line")" = $'spacelift\tCould not notify VCS:' ]
  [ "$(cut -f4 <<<"$line")" = "kind:vcs-failure severity:error target:stack/sandbox-aws-account-gezzgx id:new1 count:1 link:https://loft.app.spacelift.io/stack/sandbox-aws-account-gezzgx | could not query GitHub API: POST https://api.github.com/repos/loft-sh/terraform-modules/check-runs: 500" ]

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(record_count)" -eq 1 ]
}

@test "a new notification is one record; an account-level one links the app" {
  node a1 1 60 false WARNING run-updated stack/s1 "first" "x"
  serve
  run "$SCRIPT"
  node a2 1 30 false ERROR vcs-failure account "GitHub API error" $'service unavailable,\ncouldn\'t complete\tthe operation'
  serve
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [ "$(record_count)" -eq 2 ]
  [ "$(tail -n1 "$SPACELIFT_EVENTS_LOG" | cut -f4)" = "kind:vcs-failure severity:error target:account id:a2 count:1 link:https://loft.app.spacelift.io | service unavailable, couldn't complete the operation" ]
}

@test "a repeat folded into the same notification fires again with its count" {
  node r1 1 60 false ERROR vcs-failure stack/s1 "Could not notify VCS" "500"
  serve
  run "$SCRIPT"
  NODES=()
  node r1 3 10 false ERROR vcs-failure stack/s1 "Could not notify VCS" "500"
  serve
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [ "$(record_count)" -eq 2 ]
  [[ "$(tail -n1 "$SPACELIFT_EVENTS_LOG")" == *" id:r1 count:3 "* ]]
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(record_count)" -eq 2 ]
}

@test "a notification dismissed before it was seen fires nothing" {
  serve
  run "$SCRIPT"
  node d1 1 60 true INFO run-updated stack/s1 "handled" "x"
  serve
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(record_count)" -eq 0 ]
  grep -q '^d1' "${SPACELIFT_EVENTS_STATE}/seen"
}

@test "a failed read exits 1, appends nothing and keeps the state" {
  node f1 1 60 false ERROR vcs-failure stack/s1 "Could not notify VCS" "500"
  serve
  run "$SCRIPT"
  cp "${SPACELIFT_EVENTS_STATE}/seen" "${WORK}/seen.before"
  touch "${SL_FIXTURE}.fail"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"spacectl api failed"* ]]
  echo '{"errors":[{"message":"unauthorized"}]}' >"$SL_FIXTURE"
  rm -f "${SL_FIXTURE}.fail"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(record_count)" -eq 1 ]
  cmp "${SPACELIFT_EVENTS_STATE}/seen" "${WORK}/seen.before"
}

@test "an empty notification list is a clean run" {
  serve
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "SUMMARY: records=0" ]]
}
