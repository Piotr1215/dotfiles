#!/usr/bin/env bash

# shellcheck disable=SC2155
source /home/decoder/dev/dotfiles/scripts/__lib_taskwarrior_interop.sh

set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh github_issue_sync.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

# Logger with timestamp
log() {
	echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

# Removing [] from the description is needed to avoid issues with taskwarrior search engine
# Otherwise it will create duplicate tasks for the same issue on evey sync
sanitize_task() {
	local description=$1
	# Remove square brackets
	echo "${description//[\[\]]/}"
}

# Retrieve and format GitHub issues
get_issues() {
	local issues
	issues=$(gh api -X GET /search/issues \
		-f q='is:issue is:open assignee:Piotr1215' \
		--jq '.items[] | select(.state == "open") | {id: .number, description: .title, repository: .repository_url}')
	echo "$issues"
}

# Synchronize issues with Taskwarrior
sync_to_taskwarrior() {
	local issue_line issue_id issue_description issue_repo_name issue_repo sanitized_description

	issue_line=$1
	issue_id=$(echo "$issue_line" | jq -r '.id')
	issue_description=$(echo "$issue_line" | jq -r '.description')
	issue_repo_name=$(echo "$issue_line" | jq -r '.repository' | awk -F'/' '{print $6}')
	issue_repo=$(echo "$issue_line" | jq -r '.repository' | sed -e 's/api.//' -e 's/repos\///')
	sanitized_description=$(sanitize_task "$issue_description")

	# Check if the task already exists by searching for a sanitized description
	if ! task "$sanitized_description" &>/dev/null; then
		# Pass the arguments as an array to maintain separation
		local task_args=("$sanitized_description" "+github" "project:$issue_repo_name")

		# Use create_task function to add a new task with attributes
		task_id=$(create_task "${task_args[@]}") # Expand array elements as separate arguments

		# Annotate the newly created task with the issue URL
		annotate_task "$task_id" "$issue_repo/issues/$issue_id"
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

compare_and_display_tasks_not_in_github() {
	local existing_task_descriptions="$1"
	local github_issues="$2"
	local task_description
	local issue_description
	local issue_exists

	log "Starting comparison of Taskwarrior tasks and GitHub issues."
	# Convert the newline-separated string of existing task descriptions into an array
	mapfile -t existing_task_descriptions_array <<<"$existing_task_descriptions"
	log "Existing Taskwarrior task descriptions array: ${existing_task_descriptions_array[*]}"

	# Convert the newline-separated string of GitHub issue descriptions into an array (no need to parse JSON)
	mapfile -t github_issue_descriptions_array <<<"$github_issues"
	log "GitHub issue descriptions array: ${github_issue_descriptions_array[*]}"

	# Iterate over each Taskwarrior task description in the array
	for task_description in "${existing_task_descriptions_array[@]}"; do
		# Trim the task description to remove any leading/trailing whitespace
		local trimmed_task_description=$(echo "$task_description" | xargs)
		# Initialize issue_exists as false
		issue_exists=false
		# Check if the trimmed task description exists in the GitHub issues (case-insensitive comparison)
		for issue_description in "${github_issue_descriptions_array[@]}"; do
			local trimmed_issue_description=$(echo "$issue_description" | xargs)
			if [[ "${trimmed_task_description,,}" == "${trimmed_issue_description,,}" ]]; then
				issue_exists=true
				break
			fi
		done
		# If the task does not exist in GitHub issues, mark it as completed
		if [[ "$issue_exists" == false ]]; then
			sync_github_issue "$task_description"
		fi
	done
}

# Follow the Python convention and execute the main function
main() {
	local issues
	local existing_task_ids
	local github_issues
	local task_id
	local description

	issues=$(get_issues)
	log "Retrieved GitHub issues: $issues"

	echo "$issues" | while IFS= read -r line; do
		sync_to_taskwarrior "$(echo "$line" | jq -c '.')"
	done
	existing_task_ids=$(task +github export | jq -r '.[] | select(.status == "pending") | .description' | while read -r line; do sanitize_task "$line"; done)
	log "Existing Taskwarrior task descriptions: $existing_task_ids"
	github_issues=$(echo "$issues" | jq -r '. | .description' | while read -r line; do sanitize_task "$line"; done)
	log "GitHub issue descriptions: $github_issues"

	compare_and_display_tasks_not_in_github "$existing_task_ids" "$github_issues"
}
# Simulate entry point call
main
