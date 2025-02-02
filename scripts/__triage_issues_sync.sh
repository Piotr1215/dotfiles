#!/usr/bin/env bash
set -eo pipefail

source /home/decoder/dev/dotfiles/scripts/__lib_taskwarrior_interop.sh

# Override get_task_id_by_description to include triage tag
get_task_id_by_description() {
	local description="$1"
	task +triage status:pending export |
		jq -r --arg desc "$description" '.[] | select(.description == $desc) | .uuid'
}

# Get triage issues from Linear
get_triage_issues() {
	curl -s -X POST \
		-H "Content-Type: application/json" \
		-H "Authorization: $LINEAR_API_KEY" \
		--data '{"query": "query { issues(filter: {state: {name: {eq: \"Triage\"}}, team: {name: {eq: \"Docs\"}}}) { nodes { id identifier number title url team { name } } } }"}' \
		https://api.linear.app/graphql | jq -r '.data.issues.nodes[]'
}

# Main function
main() {
	local issue_title issue_id issue_url task_uuid
	local issues_added=0

	# Using process substitution instead of pipe to avoid subshell
	while read -r issue; do
		issue_title=$(echo "$issue" | jq -r '.title')
		issue_id=$(echo "$issue" | jq -r '.identifier')
		issue_url=$(echo "$issue" | jq -r '.url')

		task_uuid=$(get_task_id_by_description "$issue_title")

		if [[ -z "$task_uuid" ]]; then
			echo "Creating new task for: $issue_title"
			# Append `|| true` so any non-zero exit doesn't kill the script
			task_uuid=$(create_task "$issue_title" "+triage" "project:docs-maintenance" "session:vdocs" "linear_issue_id:$issue_id") || true
			annotate_task "$task_uuid" "$issue_url" || true

			issues_added=$((issues_added + 1))

		else
			echo "Task already exists for: $issue_title"
		fi
	done < <(get_triage_issues | jq -c '.')

	# Optional: force exit 0 if you want to always succeed
	# exit 0
}

main
