#!/usr/bin/env bash

# shellcheck disable=SC2155
source /home/decoder/dev/dotfiles/scripts/__lib_taskwarrior_interop.sh

set -eo pipefail

IFS=$'\n\t'

log_message() {
	echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

sanitize_description() {
	local description="$1"
	echo "${description//[\[\]]/}"
}

fetch_github_issues() {
	local issues
	issues=$(gh api -X GET /search/issues -f q='is:issue is:open assignee:Piotr1215' --jq '.items[] | select(.state == "open") | {id: .number, description: .title, repository: .repository_url}')
	echo "$issues"
}

sync_issue_to_task() {
	local issue="$1"
	local issue_id=$(echo "$issue" | jq -r '.id')
	local description=$(echo "$issue" | jq -r '.description')
	local repo_name=$(echo "$issue" | jq -r '.repository' | awk -F'/' '{print $6}')
	local repo_url=$(echo "$issue" | jq -r '.repository' | sed -e 's/api.//' -e 's/repos\///')
	local clean_description=$(sanitize_description "$description")

	if ! task "$clean_description" &>/dev/null; then
		local task_args=("$clean_description" "+github" "project:$repo_name")
		local task_id=$(create_task "${task_args[@]}")
		annotate_task "$task_id" "$repo_url/issues/$issue_id"
		log_message "Task created for: $clean_description"
	else
		log_message "Task already exists for: $clean_description"
	fi
}

compare_and_update_tasks() {
	local existing_tasks="$1"
	local github_issues="$2"
	local issue_exists

	log_message "Comparing Taskwarrior tasks with GitHub issues."
	mapfile -t existing_tasks_array <<<"$existing_tasks"
	mapfile -t github_issues_array <<<"$github_issues"

	for task_description in "${existing_tasks_array[@]}"; do
		local trimmed_description=$(echo "$task_description" | xargs)
		issue_exists=false

		for issue_description in "${github_issues_array[@]}"; do
			local trimmed_issue=$(echo "$issue_description" | xargs)
			if [[ "${trimmed_description,,}" == "${trimmed_issue,,}" ]]; then
				issue_exists=true
				break
			fi
		done

		if [[ "$issue_exists" == false ]]; then
			update_github_issue_status "$task_description"
		fi
	done
}

update_github_issue_status() {
	local description="$1"
	local task_id=$(get_task_id_by_description "$description")
	if [[ -n "$task_id" ]]; then
		mark_task_as_completed "$task_id"
		log_message "Task marked as completed: $description"
	else
		log_message "Task ID not found for: $description"
	fi
}

main() {
	local issues=$(fetch_github_issues)
	log_message "Retrieved GitHub issues: $issues"

	echo "$issues" | while IFS= read -r line; do
		sync_issue_to_task "$line"
	done

	local existing_tasks=$(task +github export | jq -r '.[] | select(.status == "pending") | .description' | while read -r line; do sanitize_description "$line"; done)
	log_message "Existing Taskwarrior tasks: $existing_tasks"
	local github_descriptions=$(echo "$issues" | jq -r '. | .description' | while read -r line; do sanitize_description "$line"; done)
	log_message "GitHub issue descriptions: $github_descriptions"

	compare_and_update_tasks "$existing_tasks" "$github_descriptions"
}

main
