#!/usr/bin/env bash
# __create_linear_issue.sh - Creates a Linear issue from taskwarrior task
set -eo pipefail

exec 1> >(tee -a /tmp/linear_create.log) 2>&1

uuid="$1"

if [ -z "$uuid" ]; then
	echo "Error: Task UUID not provided"
	exit 1
fi

# Get task details
TASK_DETAILS=$(task "$uuid" export)
TASK_DESCRIPTION=$(echo "$TASK_DETAILS" | jq -r '.[0].description')

# Create markdown template
DESCRIPTION=$(jq -r '[.[0].annotations[]?.description | select(test("^(what|brief|done-when):"; "i"))] | if length == 0 then error("handoff has no what, brief or done-when annotations") else join("\n\n") end' <<< "$TASK_DETAILS")

# Team config - edit when teams rename
LINEAR_TEAM_ID="${LINEAR_DEVOPS_TEAM_ID:-$LINEAR_OPS_TEAM_ID}"

# Resolve the exact team's Triage state before creating an issue.
lookup_query=$(jq -n --arg team "$LINEAR_TEAM_ID" '{
  query: "query TeamStates($team: String!) { team(id: $team) { id states(first: 250) { nodes { id name } pageInfo { hasNextPage } } } }",
  variables: {team: $team}
}')
if ! lookup_response=$(curl -fsS -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_KEY" \
  --data "$lookup_query" https://api.linear.app/graphql); then
  echo "Failed to look up Linear Triage state" >&2
  exit 1
fi
if ! state_id=$(jq -er --arg team "$LINEAR_TEAM_ID" '
  if (.errors // [] | length) != 0 or .data.team.id != $team or
     .data.team.states.pageInfo.hasNextPage != false or
     (.data.team.states.nodes | type) != "array" then error("invalid state lookup")
  else [.data.team.states.nodes[] | select(.name == "Triage") | .id] |
    if length == 1 and (.[0] | type == "string" and length > 0) then .[0]
    else error("missing or ambiguous Triage state") end
  end' <<< "$lookup_response"); then
  echo "Failed to resolve a unique Linear Triage state" >&2
  exit 1
fi

# Construct the GraphQL mutation using jq
query=$(jq -n \
	--arg title "$TASK_DESCRIPTION" \
	--arg desc "$DESCRIPTION" \
	--arg team "$LINEAR_TEAM_ID" \
	--arg state "$state_id" \
	'{
    query: "mutation IssueCreate($title: String!, $desc: String!, $team: String!, $state: String!) {
      issueCreate(input: {
        title: $title,
        description: $desc,
        teamId: $team,
        stateId: $state
      }) {
        success
        issue {
          id
          title
          url
          number
        }
      }
    }",
    variables: {
      title: $title,
      desc: $desc,
      team: $team,
      state: $state
    }
  }')

# Create the issue
response=$(curl -s -X POST \
	-H "Content-Type: application/json" \
	-H "Authorization: $LINEAR_API_KEY" \
	--data "$query" \
	https://api.linear.app/graphql)

echo "Response: $response"

# Extract issue ID and URL
issue_url=$(echo "$response" | jq -r '.data.issueCreate.issue.url')
# Extract identifier from URL (e.g., DEVOPS-68) - handles team renames automatically
linear_issue_id=$(echo "$issue_url" | grep -oE '[A-Z]+-[0-9]+')

if [ -n "$linear_issue_id" ] && [ "$linear_issue_id" != "null" ]; then
	# uda.repo.default=no-repo marks a task with no repo; once it has an issue the
	# repo must be unset again so the team-prefix derivation and triage apply.
	if [ "$(task _get "${uuid}.repo" 2>/dev/null)" = "no-repo" ]; then
		task "$uuid" modify linear_issue_id:"$linear_issue_id" repo:
	else
		task "$uuid" modify linear_issue_id:"$linear_issue_id"
	fi
	task "$uuid" annotate "$issue_url"
else
	echo "Failed to create Linear issue"
	echo "Response: $response"
	exit 1
fi
