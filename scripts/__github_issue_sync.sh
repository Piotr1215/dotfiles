#!/usr/bin/env bash

# shellcheck disable=SC2155
source /home/decoder/dev/dotfiles/scripts/__lib_taskwarrior_interop.sh

set -eo pipefail

# Add source and line number when running in debug mode: __run_with_xtrace.sh github_issue_sync.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

# Logger with timestamp
log() {
	echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

# Removing [] from the description is needed to avoid issues with taskwarrior search engine
# Otherwise it will create duplicate tasks for the same issue on every sync
sanitize_task() {
	local description=$1
	# Remove square brackets
	echo "${description//[\[\]]/}"
}

# Retrieve and format GitHub issues
get_github_issues() {
	local issues
	if ! issues=$(gh api -X GET /search/issues \
		-f q='is:issue is:open assignee:Piotr1215' \
		--jq '.items[] | select(.state == "open") | {id: .number, description: .title, repository: .repository_url}'); then
		echo "Error: Unable to fetch GitHub issues"
		return 1
	fi
	echo "$issues"
}

# Retrieve and format Linear issues
get_linear_issues() {
	local issues
	if ! issues=$(curl -s -X POST \
		-H "Content-Type: application/json" \
		-H "Authorization: $LINEAR_API_KEY" \
		--data '{"query": "query { user(id: \"'"$LINEAR_USER_ID"'\") { id name assignedIssues(filter: { state: { name: { neq: \"Released\" } } }) { nodes { id title } } } }"}' \
		https://api.linear.app/graphql | jq -r '.data.user.assignedIssues.nodes[] | {id: .id, description: .title, repository: ("linear" | ascii_downcase)}'); then
		echo "Error: Unable to fetch Linear issues"
		return 1
	fi
	echo "$issues"
}

# Synchronize issues with Taskwarrior
sync_to_taskwarrior() {
	local issue_line issue_id issue_description issue_repo_name sanitized_description

	issue_line=$1
	issue_id=$(echo "$issue_line" | jq -r '.id')
	issue_description=$(echo "$issue_line" | jq -r '.description')
	issue_repo_name=$(echo "$issue_line" | jq -r '.repository')
	sanitized_description=$(sanitize_task "$issue_description")

	# Check if the task already exists by searching for a sanitized description
	if ! task "$sanitized_description" &>/dev/null; then
		# Pass the arguments as an array to maintain separation
		local task_args=("$sanitized_description" "+$issue_repo_name" "project:$issue_repo_name")

		# Use create_task function to add a new task with attributes
		task_id=$(create_task "${task_args[@]}") # Expand array elements as separate arguments

		# Annotate the newly created task with the issue URL
		log "Task created for: $sanitized_description"
	else
		log "Task already exists for: $sanitized_description"
	fi
}

sync_github_issue() {
	local task_description=$1
	local task_id=$(get_task_id_by_description "$task_description")
	if [[ -n "$task_id" ]]; then
		mark_task_completed "$task_id"
		log "Task marked as completed: $task_description"
	else
		log "Task ID not found for: $task_description"
	fi
}

compare_and_display_tasks_not_in_issues() {
	local existing_task_descriptions="$1"
	local issues_descriptions="$2"
	local task_description
	local issue_description
	local issue_exists

	log "Starting comparison of Taskwarrior tasks and issues."
	# Convert the newline-separated string of existing task descriptions into an array
	mapfile -t existing_task_descriptions_array <<<"$existing_task_descriptions"

	# Convert the newline-separated string of issue descriptions into an array (no need to parse JSON)
	mapfile -t issues_descriptions_array <<<"$issues_descriptions"

	# Iterate over each Taskwarrior task description in the array
	for task_description in "${existing_task_descriptions_array[@]}"; do
		# Trim the task description to remove any leading/trailing whitespace
		local trimmed_task_description=$(echo "$task_description" | xargs)
		# Initialize issue_exists as false
		issue_exists=false
		# Check if the trimmed task description exists in the issues (case-insensitive comparison)
		for issue_description in "${issues_descriptions_array[@]}"; do
			local trimmed_issue_description=$(echo "$issue_description" | xargs)
			if [[ "${trimmed_task_description,,}" == "${trimmed_issue_description,,}" ]]; then
				issue_exists=true
				break
			fi
		done
		# If the task does not exist in issues, mark it as completed
		if [[ "$issue_exists" == false ]]; then
			sync_github_issue "$task_description"
		fi
	done
	log "Comparison of Taskwarrior tasks and issues completed."
}

# Main function to orchestrate syncing
main() {
	local github_issues
	local linear_issues
	local existing_task_descriptions

	# Get GitHub issues and Linear issues
	github_issues=$(get_github_issues)
	linear_issues=$(get_linear_issues)

	# Log retrieved issues
	log "Retrieved GitHub issues: $(echo "$github_issues" | jq .)"
	log "Retrieved Linear issues: $(echo "$linear_issues" | jq .)"

	# Sync GitHub issues to Taskwarrior
	echo "$github_issues" | jq -c '.' | while IFS= read -r line; do
		sync_to_taskwarrior "$line"
	done

	# Sync Linear issues to Taskwarrior
	echo "$linear_issues" | jq -c '.' | while IFS= read -r line; do
		sync_to_taskwarrior "$line"
	done

	# Get existing Taskwarrior tasks
	existing_task_descriptions=$(task +github export | jq -r '.[] | select(.status == "pending") | .description' | while read -r line; do sanitize_task "$line"; done)

	# Compare and display tasks not in GitHub and Linear issues
	compare_and_display_tasks_not_in_issues "$existing_task_descriptions" "$(
		echo "$github_issues" | jq -r '.description'
		echo "$linear_issues" | jq -r '.description'
	)"
}

# Simulate entry point call
main
