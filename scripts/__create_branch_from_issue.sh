#!/usr/bin/env bash

set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __create_branch_from_issue.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

get_linear_issues() {
	curl -s -X POST \
		-H "Content-Type: application/json" \
		-H "Authorization: $LINEAR_API_KEY" \
		--data '{"query": "query { user(id: \"'"$LINEAR_USER_ID"'\") { id name assignedIssues(filter: { state: { name: { nin: [\"Released\", \"Canceled\"] } } }) { nodes { id title url } } } }"}' \
		https://api.linear.app/graphql
}

extract_issue_id() {
	sed -n 's/.*\/issue\/\([^/]\+\)\/.*/\1/p' | tr '[:upper:]' '[:lower:]'
}

create_interactive_branch() {
	echo "Fetching issues and branches..."

	# Get current git branches (only those starting with potential issue IDs)
	current_branches=$(git branch --format="%(refname:short)" | grep -E '^[a-zA-Z]+-[0-9]+')

	# Get Linear issues and filter in one pass
	filtered_issues=$(get_linear_issues | jq -r '.data.user.assignedIssues.nodes[] | 
    select(.url | split("/")[-2] | ascii_downcase | 
    inside($branches) | not) | 
    .title + " (" + .url + ")"' --arg branches "$current_branches")

	# Check if there are any issues left after filtering
	if [ -z "$filtered_issues" ]; then
		echo "No new issues to create branches for. Exiting."
		return 1
	fi

	echo "Select an issue:"
	selected_issue=$(echo "$filtered_issues" | fzf --height 40% --reverse)

	if [ -z "$selected_issue" ]; then
		echo "No issue selected. Exiting."
		return 1
	fi

	# Extract the URL and issue ID from the selected issue
	issue_url=$(echo "$selected_issue" | grep -o '(http[^)]\+)' | tr -d '()')
	issue_id=$(echo "$issue_url" | extract_issue_id)

	# Prompt for branch name
	read -p "Enter a name for your branch: " branch_name

	# Create the new branch name
	new_branch="${issue_id}/${branch_name}"

	git checkout main

	# Create and checkout the new branch
	git checkout -b "$new_branch"

	echo "Created and checked out new branch: $new_branch"
}

# Call the function to create an interactive branch
create_interactive_branch
