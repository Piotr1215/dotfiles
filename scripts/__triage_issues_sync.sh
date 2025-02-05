#!/usr/bin/env bash
set -eo pipefail
source /home/decoder/dev/dotfiles/scripts/__lib_taskwarrior_interop.sh
get_task_id_by_description() {
	local description="$1"
	task +triage status:pending export |
		jq -r --arg desc "$description" '.[] | select(.description == $desc) | .uuid'
}
get_all_triage_tasks() {
	task +triage status:pending export |
		jq -r '.[] | .description'
}
get_triage_issues() {
	curl -s -X POST \
		-H "Content-Type: application/json" \
		-H "Authorization: $LINEAR_API_KEY" \
		--data '{"query": "query { issues(filter: {state: {name: {eq: \"Triage\"}}, team: {name: {eq: \"Docs\"}}}) { nodes { id identifier number title url team { name } } } }"}' \
		https://api.linear.app/graphql | jq -r '.data.issues.nodes[]'
}
main() {
	local issue_title issue_id issue_url task_uuid
	local issues_added=0
	local linear_issues
	linear_issues=$(get_triage_issues | jq -r '.title')
	while read -r task_desc; do
		if ! echo "$linear_issues" | grep -Fxq "$task_desc"; then
			task_uuid=$(get_task_id_by_description "$task_desc")
			echo "Deleting task no longer in triage: $task_desc"
			echo "yes" | task "$task_uuid" delete
		fi
	done < <(get_all_triage_tasks)
	while read -r issue; do
		issue_title=$(echo "$issue" | jq -r '.title')
		issue_id=$(echo "$issue" | jq -r '.identifier')
		issue_url=$(echo "$issue" | jq -r '.url')
		task_uuid=$(get_task_id_by_description "$issue_title")
		if [[ -z "$task_uuid" ]]; then
			echo "Creating new task for: $issue_title"
			task_uuid=$(create_task "$issue_title" "+triage" "project:docs-maintenance" "session:vdocs" "linear_issue_id:$issue_id") || true
			annotate_task "$task_uuid" "$issue_url" || true
			issues_added=$((issues_added + 1))
		else
			echo "Task already exists for: $issue_title"
		fi
	done < <(get_triage_issues | jq -c '.')
}
main
