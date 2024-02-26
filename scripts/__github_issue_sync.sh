#!/usr/bin/env bash

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

# Follow the Python convention and execute the main function
main() {
	local issues

	issues=$(get_issues)

	echo "$issues" | jq -c '.' | while IFS= read -r line; do
		sync_to_taskwarrior "$line"
	done
	# existing_task_ids=$(task +github export | jq -r '.[] | select(.status == "pending") | "\(.id) \(.description)"')
	# github_issues=$(echo "$issues" | jq -r '. | "\(.description)"')
	# echo "$github_issues"
	# echo "$existing_task_ids"
	# # Loop through Taskwarrior tasks
	# echo "$existing_task_ids" | while IFS= read -r line; do
	# # Extract task ID and description
	# task_id=$(echo "$line" | awk '{print $1}')
	# description=$(echo "$line" | cut -d' ' -f2-)

	# # Check if the task description is not in GitHub issues
	# if ! echo "$github_issues" | grep -Fxq "$description"; then
	# # Mark task as completed if the description is not found
	# mark_task_completed "$task_id"
	# fi
	# done
}

# Simulate entry point call
main
