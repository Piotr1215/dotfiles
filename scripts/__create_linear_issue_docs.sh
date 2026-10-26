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

# No assignee and no state: Linear files the issue unassigned in the team's
# default state (Triage), and Piotr assigns it by hand.
# Construct the GraphQL mutation using jq
query=$(jq -n \
	--arg title "$TASK_DESCRIPTION" \
	--arg desc "$DESCRIPTION" \
	--arg team "$LINEAR_DOCS_TEAM_ID" \
	'{
    query: "mutation IssueCreate($title: String!, $desc: String!, $team: String!) {
      issueCreate(input: {
        title: $title,
        description: $desc,
        teamId: $team
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
      team: $team
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
