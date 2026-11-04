#!/usr/bin/env bash
# A stable Linear UUID makes retries safe after a lost response or failed task write.
set -eo pipefail
uuid=${1:?Task UUID required}
[[ "$uuid" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]] || { echo 'A full task UUID is required' >&2; exit 1; }
task_details=$(task rc.context=none "$uuid" export)
existing=$(jq -er 'if length == 1 then .[0].linear_issue_id // "" else error("task not found") end' <<< "$task_details")
if [[ -n "$existing" ]]; then
  printf 'Task already linked to %s\n' "$existing"
  exit 0
fi
title=$(jq -er '.[0].description | select(type == "string" and length > 0)' <<< "$task_details")
description=$(jq -er '[.[0].annotations[]?.description | select(test("^(what|brief|done-when):"; "i"))] | if length == 0 then error("handoff has no brief") else join("\n\n") end' <<< "$task_details")
team=${LINEAR_DEVOPS_TEAM_ID:-${LINEAR_OPS_TEAM_ID:-}}
[[ -n "$team" && -n "${LINEAR_API_KEY:-}" ]] || { echo 'Linear team or API key missing' >&2; exit 1; }
issue_id=$(python3 - "$uuid" <<'PY'
import hashlib, sys, uuid
value = hashlib.sha256(('taskwarrior-handoff:' + sys.argv[1].lower()).encode()).digest()[:16]
print(uuid.UUID(bytes=value, version=4))
PY
)
api() {
  curl -fsS -X POST -H 'Content-Type: application/json' -H "Authorization: $LINEAR_API_KEY" --data "$1" https://api.linear.app/graphql
}
lookup=$(jq -n --arg team "$team" '{query:"query TeamStates($team: String!) { team(id: $team) { id states(first: 250) { nodes { id name } pageInfo { hasNextPage } } } }",variables:{team:$team}}')
lookup_response=$(api "$lookup") || { echo 'Failed to look up Linear Triage state' >&2; exit 1; }
state=$(jq -er --arg team "$team" '
  if (.errors // [] | length) != 0 or .data.team.id != $team or .data.team.states.pageInfo.hasNextPage != false or (.data.team.states.nodes | type) != "array" then error("invalid state lookup")
  else [.data.team.states.nodes[] | select(.name == "Triage") | .id] | if length == 1 and (.[0] | type == "string" and length > 0) then .[0] else error("missing or ambiguous Triage state") end end' <<< "$lookup_response") || { echo 'Failed to resolve Linear Triage state' >&2; exit 1; }
create=$(jq -n --arg id "$issue_id" --arg title "$title" --arg desc "$description" --arg team "$team" --arg state "$state" '{query:"mutation IssueCreate($id: String!, $title: String!, $desc: String!, $team: String!, $state: String!) { issueCreate(input: {id: $id, title: $title, description: $desc, teamId: $team, stateId: $state}) { success issue { id identifier url team { id } } } }", variables:{id:$id,title:$title,desc:$desc,team:$team,state:$state}}')
response=$(api "$create") || response=''
issue=$(jq -ec --arg id "$issue_id" --arg team "$team" 'select((.errors // [] | length) == 0 and .data.issueCreate.success == true) | .data.issueCreate.issue | select(.id == $id and .team.id == $team and (.identifier | type == "string" and test("^[A-Z]+-[0-9]+$")) and (.url | type == "string" and startswith("https://linear.app/")))' <<< "$response" 2>/dev/null) || issue=''
if [[ -z "$issue" ]]; then
  # The mutation may have committed despite a failed response or a prior retry.
  # Only attach a matching ID and team; never assume a failed lookup means absent.
  query=$(jq -n --arg id "$issue_id" '{query:"query ExistingIssue($id: String!) { issue(id: $id) { id identifier url team { id } } }",variables:{id:$id}}')
  response=$(api "$query") || { echo 'Issue creation outcome unknown; retry this action' >&2; exit 1; }
  issue=$(jq -ec --arg id "$issue_id" --arg team "$team" 'select((.errors // [] | length) == 0) | .data.issue | select(.id == $id and .team.id == $team and (.identifier | type == "string" and test("^[A-Z]+-[0-9]+$")) and (.url | type == "string" and startswith("https://linear.app/")))' <<< "$response" 2>/dev/null) || { echo 'Issue creation failed or outcome unknown; retry this action' >&2; exit 1; }
fi
identifier=$(jq -r '.identifier' <<< "$issue")
url=$(jq -r '.url' <<< "$issue")
repo=$(jq -r '.[0].repo // ""' <<< "$task_details")
if [[ "$repo" == no-repo ]]; then
  task rc.context=none "$uuid" modify "linear_issue_id:$identifier" repo:
else
  task rc.context=none "$uuid" modify "linear_issue_id:$identifier"
fi
task rc.context=none "$uuid" annotate "$url"
