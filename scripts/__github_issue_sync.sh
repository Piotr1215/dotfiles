#!/usr/bin/env bash

# github_issue_sync.sh
# Synchronizes GitHub and Linear issues with Taskwarrior
# PROJECT: taskwarrior-sync
#
# Key behaviors:
# 1. For unassigned Linear issues: Deletes them from Taskwarrior (since they're no longer relevant to you)
# 2. For completed Linear issues: Only marks as done if truly in a completed state
#    (Released, Canceled, Done, Ready for Release)
# 3. The +backlog tag is now Taskwarrior-internal and doesn't sync with Linear
#    (users can add/remove this tag manually without affecting Linear)
# 4. Tasks with +backlog or +review tags will NOT have their status, priority or tags
#    modified by the sync process, regardless of Linear issue status

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

# Check the true status of a Linear issue
check_linear_issue_status() {
	local issue_id="$1"

	# Make API call to get the specific issue's status
	local status
	status=$(curl -s -X POST \
		-H "Content-Type: application/json" \
		-H "Authorization: $LINEAR_API_KEY" \
		--data '{"query": "query { issue(id: \"'"$issue_id"'\") { id state { name } } }"}' \
		https://api.linear.app/graphql | jq -r '.data.issue.state.name')

	# Check if the status indicates the issue is truly done
	if [[ "$status" =~ ^(Released|Canceled|Done|Ready\ for\ Release)$ ]]; then
		echo "completed"
	else
		echo "active" # Active but unassigned
	fi
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
	task_uuid=$(create_task "$issue_description" "+$issue_repo_name" "+fresh" "project:$project_name")
	if [[ -n "$task_uuid" ]]; then
		annotate_task "$task_uuid" "$issue_url"
		log "Task created and annotated for: $issue_description"
		task modify "$task_uuid" linear_issue_id:"$issue_number"

		# Check task for special tags right after creation
		# This handles cases where tags might have been added via hooks
		local task_json
		local has_backlog="false"
		local has_review="false"

		# Use task export JSON for this specific task
		task_json=$(task "$task_uuid" export 2>/dev/null)

		# Check for special tags
		if [[ -n "$task_json" ]]; then
			has_backlog=$(echo "$task_json" | jq -r '.[0].tags | if . then contains(["backlog"]) else false end')
			has_review=$(echo "$task_json" | jq -r '.[0].tags | if . then contains(["review"]) else false end')
			log "Special tag check for new task: has_backlog=$has_backlog, has_review=$has_review"
		fi

		# Only apply Todo/In Progress status if no special tags are present
		if [[ "$has_backlog" != "true" && "$has_review" != "true" ]]; then
			# Handle Todo and In Progress statuses - backlog is now a Taskwarrior-only tag
			if [[ "$issue_status" == "Todo" || "$issue_status" == "In Progress" ]]; then
				# Check if manual_priority is already set
				local current_priority
				current_priority=$(task _get "$task_uuid".manual_priority 2>/dev/null || echo "")
				if [[ -z "$current_priority" ]]; then
					task modify "$task_uuid" manual_priority:1
				fi
			fi
		else
			log "New task has special tags. Skipping automatic status sync from Linear."
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
		# - When an issue moves to Backlog, we remove +next and reset priority
		# - The +backlog tag is now treated as Taskwarrior-internal and won't be automatically
		#   added or removed when Linear status changes
		# Check if task has +backlog or +review tags using task export JSON
		# This is more reliable than _get for tag checking
		local task_json
		local has_backlog="false"
		local has_review="false"

		# Use task export JSON for this specific task
		task_json=$(task "$task_uuid" export 2>/dev/null)

		# Check for special tags
		if [[ -n "$task_json" ]]; then
			has_backlog=$(echo "$task_json" | jq -r '.[0].tags | if . then contains(["backlog"]) else false end')
			has_review=$(echo "$task_json" | jq -r '.[0].tags | if . then contains(["review"]) else false end')
			log "Special tag check: has_backlog=$has_backlog, has_review=$has_review"
		fi

		# Skip modifying tags and priority if task has +backlog or +review
		if [[ "$has_backlog" == "true" || "$has_review" == "true" ]]; then
			log "DETECTED +backlog or +review tag. Skipping automatic status sync from Linear."
		else
			# Normal status sync logic when no special tags are present
			if [[ "$issue_status" =~ [Bb]acklog ]]; then
				log "Issue status is Backlog, removing +next tag and resetting priority"
				task modify "$task_uuid" -next manual_priority:
				# No longer adding +backlog automatically as it's now for manual Taskwarrior organization only
			elif [[ "$issue_status" == "Todo" || "$issue_status" == "In Progress" ]]; then
				log "Issue status is Todo or In Progress, checking priority"
				# No longer removing +backlog as it's now independent of Linear status
				# Check if manual_priority is already set
				local current_priority
				current_priority=$(task _get "$task_uuid".manual_priority 2>/dev/null || echo "")
				if [[ -z "$current_priority" ]]; then
					task modify "$task_uuid" manual_priority:1
				fi
			fi
		fi
	fi
}

# Compare existing Taskwarrior tasks with current issues and mark as completed if not present
# If a task has a linear_issue_id, it was created from Linear, so check its actual status
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
		echo "${issue,,}" >>"$issues_file"
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
				# Task has Linear ID and is not in current issues - check its actual status
				log "Task with Linear ID not found in current issues: $trimmed_desc"

				# Check the actual status of the Linear issue
				local issue_status
				issue_status=$(check_linear_issue_status "$linear_issue_id")

				if [[ "$issue_status" == "completed" ]]; then
					log "Issue is completed (Released/Canceled/Done/Ready for Release). Marking task as done."
					handle_task_completion "$task_uuid" "$trimmed_desc" "complete"
				else
					log "Issue is still active but unassigned. Deleting task from Taskwarrior."
					# Delete the task since it's unassigned from me
					echo "yes" | task "$task_uuid" delete
				fi
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
		# it means the task was likely reassigned to someone else or completed
		if ! echo "$all_linear_issue_ids" | grep -q "$linear_issue_id"; then
			log "Task has Linear ID $linear_issue_id but is no longer in my assigned issues: $task_description"

			# Check the actual status of the Linear issue to determine if it's completed or just unassigned
			local issue_status
			issue_status=$(check_linear_issue_status "$linear_issue_id")

			if [[ "$issue_status" == "completed" ]]; then
				log "Issue is completed (Released/Canceled/Done/Ready for Release). Marking task as done."
				handle_task_completion "$task_uuid" "$task_description" "complete"
			else
				log "Issue is still active but unassigned. Deleting task from Taskwarrior."
				# Delete the task since it's unassigned from me
				echo "yes" | task "$task_uuid" delete
			fi
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
