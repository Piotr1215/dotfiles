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
DESCRIPTION=$'## Description\n\n## Acceptance Criteria\n\n- [ ]\n\n## Related'

# First, we need to get the user ID and state ID
USER_QUERY=$(jq -n '{
    query: "query { viewer { id } workflowStates(filter: { team: { id: { eq: \"'$LINEAR_DOCS_TEAM_ID'\" } }, name: { eq: \"In Progress\" } }) { nodes { id } } }"
  }')

USER_RESPONSE=$(curl -s -X POST \
	-H "Content-Type: application/json" \
	-H "Authorization: $LINEAR_API_KEY" \
	--data "$USER_QUERY" \
	https://api.linear.app/graphql)

USER_ID=$(echo "$USER_RESPONSE" | jq -r '.data.viewer.id')
STATE_ID=$(echo "$USER_RESPONSE" | jq -r '.data.workflowStates.nodes[0].id')

# Construct the GraphQL mutation using jq
query=$(jq -n \
	--arg title "$TASK_DESCRIPTION" \
	--arg desc "$DESCRIPTION" \
	--arg team "$LINEAR_DOCS_TEAM_ID" \
	--arg assignee "$USER_ID" \
	--arg state "$STATE_ID" \
	'{
    query: "mutation IssueCreate($title: String!, $desc: String!, $team: String!, $assignee: String!, $state: String!) {
      issueCreate(input: {
        title: $title,
        description: $desc,
        teamId: $team,
        assigneeId: $assignee,
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
      assignee: $assignee,
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

# Extract issue ID, URL and number
issue_url=$(echo "$response" | jq -r '.data.issueCreate.issue.url')
issue_number=$(echo "$response" | jq -r '.data.issueCreate.issue.number')

# Construct the Linear ID (e.g., OPS-68)
linear_issue_id="DOC-${issue_number}"

if [ -n "$linear_issue_id" ] && [ "$linear_issue_id" != "null" ]; then
	task "$uuid" modify linear_issue_id:"$linear_issue_id"
	task "$uuid" annotate "$issue_url"
else
	echo "Failed to create Linear issue"
	echo "Response: $response"
	exit 1
fi
