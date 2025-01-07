#!/usr/bin/env bash

# github_issue_sync.sh
# Synchronizes GitHub and Linear issues with Taskwarrior
# PROJECT: taskwarrior-sync

# shellcheck disable=SC2155
source /home/decoder/dev/dotfiles/scripts/__lib_taskwarrior_interop.sh

set -eo pipefail

# Set new line and tab for word splitting
IFS=$'\n\t'

# Logger with timestamp
log() {
	echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

# Function to trim leading and trailing whitespace using sed
trim_whitespace() {
	local input="$1"
	echo "$input" | sed 's/^[ \t]*//;s/[ \t]*$//'
}

# Validate necessary environment variables
validate_env_vars() {
	local required_vars=(LINEAR_API_KEY LINEAR_USER_ID)
	for var in "${required_vars[@]}"; do
		if [[ -z "${!var}" ]]; then
			echo "Error: Environment variable $var is not set." >&2
			exit 1
		fi
	done
}

# Retrieve and format GitHub issues
get_github_issues() {
	local issues
	if ! issues=$(gh api -X GET /search/issues \
		-f q='is:issue is:open assignee:Piotr1215' \
		--jq '.items[] | {id: .number, description: .title, repository: .repository_url, html_url: .html_url}'); then
		echo "Error: Unable to fetch GitHub issues" >&2
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
		--data '{"query": "query { user(id: \"'"$LINEAR_USER_ID"'\") { id name assignedIssues(filter: { state: { name: { nin: [\"Released\", \"Canceled\",\"Done\",\"Ready for Release\"] } } }) { nodes { id title url project { name } } } } }"}' \
		https://api.linear.app/graphql | jq -c '.data.user.assignedIssues.nodes[] | {
            id: .id,
            description: .title,
            repository: "linear",
            html_url: .url,
            issue_id: (.url | split("/") | .[-2]),
            project: .project.name
        }'); then
		echo "Error: Unable to fetch Linear issues" >&2
		return 1
	fi
	echo "$issues"
}

# Synchronize a single issue with Taskwarrior
create_and_annotate_task() {
	local issue_description="$1"
	local issue_repo_name="$2"
	local issue_url="$3"
	local issue_number="$4"
	local project_name="$5"
	log "Creating new task for issue: $issue_description"
	task_uuid=$(create_task "$issue_description" "+$issue_repo_name" "project:$project_name")
	if [[ -n "$task_uuid" ]]; then
		annotate_task "$task_uuid" "$issue_url"
		log "Task created and annotated for: $issue_description"
		task modify "$task_uuid" linear_issue_id:"$issue_number"
		# Set session:vdocs for all DOC issues
		if [[ "$issue_number" == *"DOC"* ]]; then
			task modify "$task_uuid" session:vdocs
			task modify "$task_uuid" +kill
		fi
		# Handle project setting
		if [[ -n "$project_name" ]] && [[ "$project_name" != "null" ]]; then
			# Convert to lowercase, replace spaces with single hyphen, then remove duplicate hyphens
			local formatted_project=$(echo "$project_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/-\+/-/g')
			task modify "$task_uuid" project:"$formatted_project"

			# Check if project name contains vcluster or cloud (case insensitive)
			if echo "$formatted_project" | grep -qi 'vcluster\|cloud'; then
				task modify "$task_uuid" session:vcluster-staging
			fi
		else
			if [[ "$issue_number" == *"DOC"* ]]; then
				task modify "$task_uuid" project:docs-maintenance
			elif [[ "$issue_number" == *"OPS"* ]]; then
				task modify "$task_uuid" project:operations
			fi
		fi
	else
		log "Error: Failed to create task for: $issue_description" >&2
	fi
}

sync_to_taskwarrior() {
	local issue_line="$1"
	local issue_id issue_description issue_repo_name issue_url task_uuid issue_number project_name

	issue_id=$(echo "$issue_line" | jq -r '.id')
	issue_description=$(echo "$issue_line" | jq -r '.description')
	issue_repo_name=$(echo "$issue_line" | jq -r '.repository' | awk -F/ '{print $NF}')
	issue_url=$(echo "$issue_line" | jq -r '.html_url')
	issue_number=$(echo "$issue_line" | jq -r '.issue_id')
	project_name=$(echo "$issue_line" | jq -r '.project')

	log "Processing Issue ID: $issue_id, Description: $issue_description"

	task_uuid=$(get_task_id_by_description "$issue_description")

	if [[ -z "$task_uuid" ]]; then
		create_and_annotate_task "$issue_description" "$issue_repo_name" "$issue_url" "$issue_number" "$project_name"
	else
		log "Task already exists for: $issue_description (UUID: $task_uuid)"
	fi
}

# Mark a GitHub issue as completed in Taskwarrior
sync_github_issue() {
	local task_description="$1"
	local task_uuid

	task_uuid=$(get_task_id_by_description "$task_description")

	if [[ -n "$task_uuid" ]]; then
		mark_task_completed "$task_uuid"
		log "Task marked as completed: $task_description (UUID: $task_uuid)"
	else
		log "Task UUID not found for: $task_description" >&2
	fi
}

# Compare existing Taskwarrior tasks with current issues and mark as completed if not present
compare_and_display_tasks_not_in_issues() {
	local existing_task_descriptions="$1"
	local issues_descriptions="$2"
	local task_description issue_description
	local issue_exists

	log "Starting comparison of Taskwarrior tasks and current issues."

	mapfile -t existing_task_descriptions_array <<<"$existing_task_descriptions"
	mapfile -t issues_descriptions_array <<<"$issues_descriptions"

	for task_description in "${existing_task_descriptions_array[@]}"; do
		local trimmed_task_description
		trimmed_task_description=$(trim_whitespace "$task_description")
		issue_exists=false

		for issue_description in "${issues_descriptions_array[@]}"; do
			local trimmed_issue_description
			trimmed_issue_description=$(trim_whitespace "$issue_description")
			if [[ "${trimmed_task_description,,}" == "${trimmed_issue_description,,}" ]]; then
				issue_exists=true
				break
			fi
		done

		if [[ "$issue_exists" == false ]]; then
			log "No matching issue found for task: $trimmed_task_description. Marking as completed."
			sync_github_issue "$trimmed_task_description"
		fi
	done

	log "Comparison of Taskwarrior tasks and issues completed."
}

# Retrieve existing Taskwarrior task descriptions with +github or +linear tags and pending status
get_existing_task_descriptions() {
	task +github or +linear status:pending export |
		jq -r '.[] | .description'
}

# Synchronize all issues to Taskwarrior
sync_issues_to_taskwarrior() {
	local issues="$1"
	echo "$issues" | jq -c '.' | while IFS= read -r line; do
		sync_to_taskwarrior "$line"
	done
}

# Main function to orchestrate the synchronization
main() {
	local github_issues linear_issues existing_task_descriptions

	validate_env_vars

	github_issues=$(get_github_issues)
	linear_issues=$(get_linear_issues)

	if [[ -z "$github_issues" && -z "$linear_issues" ]]; then
		log "No issues retrieved from GitHub or Linear. Exiting."
		exit 0
	fi

	[[ -n "$github_issues" ]] && sync_issues_to_taskwarrior "$github_issues"
	[[ -n "$linear_issues" ]] && sync_issues_to_taskwarrior "$linear_issues"

	existing_task_descriptions=$(get_existing_task_descriptions)

	compare_and_display_tasks_not_in_issues "$existing_task_descriptions" "$(
		echo "$github_issues" | jq -r '.description'
		echo "$linear_issues" | jq -r '.description'
	)"
}

# Execute the main function
main
