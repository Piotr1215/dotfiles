#!/usr/bin/env bash

set -eo pipefail
IFS=$'\n\t'

get_linear_issues() {
	local response
	response=$(curl -s -w "\n%{http_code}" -X POST \
		-H "Content-Type: application/json" \
		-H "Authorization: $LINEAR_API_KEY" \
		--data '{"query": "query { user(id: \"'"$LINEAR_USER_ID"'\") { id name assignedIssues(filter: { state: { name: { nin: [\"Released\", \"Canceled\"] } } }) { nodes { id title url } } } }"}' \
		https://api.linear.app/graphql)
	
	local http_code=$(echo "$response" | tail -1)
	local content=$(echo "$response" | head -n -1)
	
	if [ "$http_code" != "200" ]; then
		echo "Error: Linear API returned HTTP $http_code" >&2
		echo "Response: $content" >&2
		return 1
	fi
	
	# Check if response is valid JSON
	if ! echo "$content" | jq empty 2>/dev/null; then
		echo "Error: Invalid JSON response from Linear API" >&2
		echo "Response: $content" >&2
		return 1
	fi
	
	echo "$content"
}

extract_issue_id() {
	echo "$1" | sed -n 's/.*\/issue\/\([^/]\+\)\/.*/\1/p' | tr -d '[]' | tr '[:upper:]' '[:lower:]'
}

create_interactive_branch() {
	current_branches=$(git branch --format="%(refname:short)" | grep -E '^[a-zA-Z]+-[0-9]+' || true)
	
	linear_issues=$(get_linear_issues)
	if [ $? -ne 0 ]; then
		echo "Failed to fetch Linear issues" >&2
		return 1
	fi

	filtered_issues=$(echo "$linear_issues" | jq -r '.data.user.assignedIssues.nodes[] | 
        (.url | split("/")[-2] | gsub("\\[|\\]"; "") | ascii_downcase) as $id |
        select($id | inside($branches) | not) | 
        .title + " (" + .url + ")"' --arg branches "$current_branches")

	if [ -z "$filtered_issues" ]; then
		echo "No new issues found to create branches from" >&2
		return 1
	fi

	selected_issue=$(echo "$filtered_issues" | fzf --height 40% --reverse)

	if [ -z "$selected_issue" ]; then
		return 1
	fi

	issue_url=$(echo "$selected_issue" | grep -o '(http[^)]\+)' | tr -d '()')
	issue_id=$(extract_issue_id "$issue_url")

	read -p "Enter a name for your branch: " branch_name

	new_branch="${issue_id}/${branch_name}"

	git checkout main
	git checkout -b "$new_branch"
}

create_interactive_branch
