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
		--data '{"query": "query { user(id: \"'"$LINEAR_USER_ID"'\") { id name assignedIssues(filter: { state: { name: { nin: [\"Released\", \"Canceled\",\"Done\",\"Ready for Release\"] } } }) { nodes { id title url state { name } project { name } } } } }"}' \
		https://api.linear.app/graphql | jq -c '.data.user.assignedIssues.nodes[] | {
            id: .id,
            description: .title,
            repository: "linear",
            html_url: .url,
            issue_id: (.url | split("/") | .[-2]),
            project: .project.name,
            status: .state.name
        }'); then
		echo "Error: Unable to fetch Linear issues" >&2
		return 1
	fi
	echo "$issues"
}

# Safely attempt to complete or delete a task based on its status and deletability
handle_task_completion() {
	local task_uuid="$1"
	local task_description="$2"
	local action="$3"
	
	# We should only handle pending tasks
	local status
	status=$(task _get "$task_uuid".status 2>/dev/null || echo "")
	
	if [[ "$status" != "pending" ]]; then
		# Skip non-pending tasks entirely
		return
	fi
	
	local is_deletable
	is_deletable=$(task _get "$task_uuid".deletable 2>/dev/null || echo "false")
	
	if [[ "$is_deletable" == "true" && "$action" == "delete" ]]; then
		log "Deleting task $task_uuid: $task_description"
		echo "yes" | task "$task_uuid" delete
	else
		log "Marking task $task_uuid as completed: $task_description"
		mark_task_completed "$task_uuid"
	fi
}

# Synchronize a single issue with Taskwarrior
create_and_annotate_task() {
	local issue_description="$1"
	local issue_repo_name="$2"
	local issue_url="$3"
	local issue_number="$4"
	local project_name="$5"
	local issue_status="$6"
	echo "Issue status: $issue_status"
	log "Creating new task for issue: $issue_description"
	task_uuid=$(create_task "$issue_description" "+$issue_repo_name" "project:$project_name")
	if [[ -n "$task_uuid" ]]; then
		annotate_task "$task_uuid" "$issue_url"
		log "Task created and annotated for: $issue_description"
		task modify "$task_uuid" linear_issue_id:"$issue_number"
		if [[ "$issue_status" == "Backlog" ]]; then
			task modify "$task_uuid" +backlog
		elif [[ "$issue_status" == "Todo" ]]; then
			task modify "$task_uuid" +next manual_priority:1
		fi
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
			# Check if project name contains vnode (case insensitive)
			if echo "$formatted_project" | grep -qi 'vnode'; then
				task modify "$task_uuid" repo:vnode-docs
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
	issue_status=$(echo "$issue_line" | jq -r '.status')

	log "Processing Issue ID: $issue_id, Description: $issue_description"

	task_uuid=$(get_task_id_by_description "$issue_description")

	if [[ -z "$task_uuid" ]]; then
		create_and_annotate_task "$issue_description" "$issue_repo_name" "$issue_url" "$issue_number" "$project_name" "$issue_status"
	else
		log "Task already exists for: $issue_description (UUID: $task_uuid)"
		
		# Update task tags and priority based on current Linear status
		# This ensures tags stay in sync when an issue's status changes in Linear
		# For example:
		# - When an issue moves to Todo, we add +next and set priority
		# - When an issue moves back to Backlog, we remove +next and reset priority
		# - This maintains correct workflow status in Taskwarrior
		if [[ "$issue_status" =~ [Bb]acklog ]]; then
			log "Issue status is Backlog, updating tags and removing priority"
			task modify "$task_uuid" -next manual_priority:
			task modify "$task_uuid" +backlog
		elif [[ "$issue_status" == "Todo" ]]; then
			log "Issue status is Todo, updating tags and setting priority"
			task modify "$task_uuid" -backlog manual_priority:1
			task modify "$task_uuid" +next
		fi
	fi
}

# Compare existing Taskwarrior tasks with current issues and mark as completed if not present
# If a task has a linear_issue_id, it was created from Linear, so try to delete it
compare_and_display_tasks_not_in_issues() {
	local issues_descriptions="$2"

	log "Starting comparison of Taskwarrior tasks and current issues."

	# OPTIMIZATION: Only get PENDING tasks with specific tags
	# This massively reduces the number of tasks to process
	local task_export=$(task '+github or +linear or linear_issue_id.any:' '-triage' status:pending export)
	
	# Remove any empty or null entries (extra safety check)
	task_export=$(echo "$task_export" | jq -c '[.[] | select(.status == "pending")]')
	
	# Extract all issue descriptions into a temporary file for faster processing
	local issues_file=$(mktemp)
	echo "$issues_descriptions" | tr -d '\r' | grep -v '^$' | while IFS= read -r issue; do
		echo "${issue,,}" >> "$issues_file"
	done
	
	# Debug count
	local tasks_count=$(echo "$task_export" | jq -r '.[] | .uuid' | wc -l)
	log "Processing $tasks_count pending tasks for comparison"
	
	# Process each task in a single pass using jq
	echo "$task_export" | jq -c '.[]' | while IFS= read -r task_json; do
		local task_uuid=$(echo "$task_json" | jq -r '.uuid')
		local description=$(echo "$task_json" | jq -r '.description')
		local status=$(echo "$task_json" | jq -r '.status')
		
		# Extra check - skip any non-pending tasks
		if [[ "$status" != "pending" ]]; then
			continue
		fi
		
		local trimmed_desc=$(trim_whitespace "$description")
		local lower_desc="${trimmed_desc,,}"
		local linear_issue_id=$(echo "$task_json" | jq -r '.linear_issue_id // empty')
		
		# Fast grep search instead of bash loop
		if ! grep -Fxq "$lower_desc" "$issues_file"; then
			if [[ -n "$linear_issue_id" && "$linear_issue_id" != "null" ]]; then
				# Task has Linear ID and is no longer assigned - try to delete it
				log "Task has Linear ID and is no longer assigned to me: $trimmed_desc"
				handle_task_completion "$task_uuid" "$trimmed_desc" "delete"
			else
				# Regular GitHub/Linear task - mark as completed
				log "No matching issue found for task: $trimmed_desc"
				handle_task_completion "$task_uuid" "$trimmed_desc" "complete"
			fi
		fi
	done
	
	# Clean up
	rm -f "$issues_file"

	log "Comparison of Taskwarrior tasks and issues completed."
}

# Synchronize all issues to Taskwarrior
sync_issues_to_taskwarrior() {
	local issues="$1"
	echo "$issues" | jq -c '.' | while IFS= read -r line; do
		sync_to_taskwarrior "$line"
	done
}

# Find tasks that have linear_issue_id but are no longer in our Linear feed
find_and_delete_reassigned_tasks() {
	local linear_issues="$1"
	local all_linear_issue_ids linear_issue_id
	
	log "Checking for reassigned Linear tasks..."
	
	# Get all tasks with linear_issue_id but exclude +triage tasks
	# OPTIMIZATION: Only get pending tasks
	local tasks_with_linear_id=$(task 'linear_issue_id.any:' '-triage' status:pending export)
	
	# Remove any empty or null entries (extra safety check)
	tasks_with_linear_id=$(echo "$tasks_with_linear_id" | jq -c '[.[] | select(.status == "pending")]')
	
	if [[ -z "$tasks_with_linear_id" || "$tasks_with_linear_id" == "[]" ]]; then
		log "No pending tasks with linear_issue_id found."
		return
	fi
	
	# Debug count
	local tasks_count=$(echo "$tasks_with_linear_id" | jq -r '.[] | .uuid' | wc -l)
	log "Processing $tasks_count pending tasks with linear_issue_id"
	
	# Get all linear issue IDs from the Linear API response
	all_linear_issue_ids=$(echo "$linear_issues" | jq -r '.issue_id // empty')
	
	# Process each task with a linear_issue_id
	echo "$tasks_with_linear_id" | jq -c '.[]' | while IFS= read -r task_data; do
		local status=$(echo "$task_data" | jq -r '.status')
		
		# Extra check - skip any non-pending tasks
		if [[ "$status" != "pending" ]]; then
			continue
		fi
		
		linear_issue_id=$(echo "$task_data" | jq -r '.linear_issue_id')
		task_uuid=$(echo "$task_data" | jq -r '.uuid')
		task_description=$(echo "$task_data" | jq -r '.description')
		
		# If the task has a linear_issue_id but it's not in our current Linear issues,
		# it means the task was likely reassigned to someone else
		if ! echo "$all_linear_issue_ids" | grep -q "$linear_issue_id"; then
			log "Task has Linear ID $linear_issue_id but is no longer assigned to me: $task_description"
			handle_task_completion "$task_uuid" "$task_description" "delete"
		fi
	done
}

# Main function to orchestrate the synchronization
main() {
	local github_issues linear_issues

	validate_env_vars

	github_issues=$(get_github_issues)
	linear_issues=$(get_linear_issues)

	if [[ -z "$github_issues" && -z "$linear_issues" ]]; then
		log "No issues retrieved from GitHub or Linear. Exiting."
		exit 0
	fi

	# Process specific deletion of reassigned Linear tasks
	[[ -n "$linear_issues" ]] && find_and_delete_reassigned_tasks "$linear_issues"

	# Normal sync process
	[[ -n "$github_issues" ]] && sync_issues_to_taskwarrior "$github_issues"
	[[ -n "$linear_issues" ]] && sync_issues_to_taskwarrior "$linear_issues"

	# Directly pass issue descriptions to the optimized comparison function
	compare_and_display_tasks_not_in_issues "" "$(
		echo "$github_issues" | jq -r '.description'
		echo "$linear_issues" | jq -r '.description'
	)"
	echo "Syncing triage issues"

	if systemctl --user start triage-sync.service; then
		log "Triage issues synced successfully"
	else
		log "Error: Failed to sync triage issues" >&2
	fi
}

# Execute the main function
main