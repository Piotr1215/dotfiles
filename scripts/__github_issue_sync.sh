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

# ====================================================
# LOGGING FUNCTIONS
# ====================================================

# Logger with timestamp
log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

# Function to trim leading and trailing whitespace using sed
trim_whitespace() {
    local input="$1"
    echo "$input" | sed 's/^[ \t]*//;s/[ \t]*$//'
}

# ====================================================
# PHASE 1: ENVIRONMENT AND SETUP
# ====================================================

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

# ====================================================
# PHASE 2: DATA FETCHING
# ====================================================

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
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: $LINEAR_API_KEY" \
        --data '{"query": "query { user(id: \"'"$LINEAR_USER_ID"'\") { id name assignedIssues(filter: { state: { name: { nin: [\"Released\", \"Canceled\",\"Done\",\"Ready for Release\"] } } }) { nodes { id title url state { name } project { name } } } } }"}' \
        https://api.linear.app/graphql)
    
    local http_code=$(echo "$response" | tail -1)
    local content=$(echo "$response" | head -n -1)
    
    if [ "$http_code" != "200" ]; then
        echo "Error: Linear API returned HTTP $http_code" >&2
        echo "Response: $content" >&2
        return 1
    fi
    
    # Check if response is valid JSON
    if ! echo "$content" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON response from Linear API" >&2
        echo "Response: $content" >&2
        return 1
    fi
    
    # Check for API errors in the response
    local errors=$(echo "$content" | jq -r '.errors // empty')
    if [ -n "$errors" ]; then
        echo "Error: Linear API returned errors: $errors" >&2
        return 1
    fi
    
    # Parse the issues
    local issues
    if ! issues=$(echo "$content" | jq -c '.data.user.assignedIssues.nodes[] | {
            id: .id,
            description: .title,
            repository: "linear",
            html_url: .url,
            issue_id: (.url | split("/") | .[-2]),
            project: .project.name,
            status: .state.name
        }' 2>/dev/null); then
        echo "Error: Failed to parse Linear issues" >&2
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

# ====================================================
# PHASE 3: TASK MANAGEMENT
# ====================================================

# Safely attempt to complete or delete a task based on its status and deletability
handle_task_completion() {
    local task_uuid="$1"
    local task_description="$2"
    local action="$3"
    
    # Validate task UUID
    if [[ -z "$task_uuid" || "$task_uuid" == "null" ]]; then
        log "WARNING: Cannot complete task - invalid task UUID: '$task_uuid'"
        return
    fi

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
        task rc.confirmation=no "$task_uuid" delete
    else
        log "Marking task $task_uuid as completed: $task_description"
        mark_task_completed "$task_uuid"
    fi
}

# Manage specific Project and Session settings
manage_project_settings() {
    local task_uuid="$1"
    local project_name="$2"
    local issue_number="$3"
    
    # Validate task UUID
    if [[ -z "$task_uuid" || "$task_uuid" == "null" ]]; then
        log "WARNING: Cannot manage project settings - invalid task UUID: '$task_uuid'"
        return
    fi

    # Handle project setting
    if [[ -n "$project_name" ]] && [[ "$project_name" != "null" ]]; then
        # Convert to lowercase, replace spaces with single hyphen, then remove duplicate hyphens
        local formatted_project
        formatted_project=$(echo "$project_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/-\+/-/g')
        task rc.confirmation=no modify "$task_uuid" project:"$formatted_project"

        # Check if project name contains vcluster or cloud (case insensitive)
        if echo "$formatted_project" | grep -qi 'vcluster\|cloud'; then
            task rc.confirmation=no modify "$task_uuid" session:vcluster-staging
        fi

        if echo "$formatted_project" | grep -qi 'vclustercloud-maintenance'; then
            task rc.confirmation=no modify "$task_uuid" repo:hosted-platform
        fi

        # Check if project name contains vnode (case insensitive)
        if echo "$formatted_project" | grep -qi 'vnode'; then
            task rc.confirmation=no modify "$task_uuid" repo:vnode-docs
        fi
    else
        if [[ "$issue_number" == *"DOC"* ]]; then
            task rc.confirmation=no modify "$task_uuid" project:docs-maintenance
        elif [[ "$issue_number" == *"OPS"* ]]; then
            task rc.confirmation=no modify "$task_uuid" project:operations
        fi
    fi

    # Set session:vdocs for all DOC issues
    if [[ "$issue_number" == *"DOC"* ]]; then
        task rc.confirmation=no modify "$task_uuid" session:vdocs
        task rc.confirmation=no modify "$task_uuid" +kill
    fi
}

# Update task tags and priority based on Linear issue status
update_task_status() {
    local task_uuid="$1"
    local issue_status="$2"
    
    # Validate task UUID
    if [[ -z "$task_uuid" || "$task_uuid" == "null" ]]; then
        log "WARNING: Cannot update task status - invalid task UUID: '$task_uuid'"
        return
    fi
    
    # Check if task has +backlog or +review tags using task export JSON
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
            task rc.confirmation=no modify "$task_uuid" -next manual_priority:
        elif [[ "$issue_status" == "Todo" || "$issue_status" == "In Progress" ]]; then
            log "Issue status is Todo or In Progress, checking priority"
            # Check if manual_priority is already set
            local current_priority
            current_priority=$(task _get "$task_uuid".manual_priority 2>/dev/null || echo "")
            if [[ -z "$current_priority" ]]; then
                task rc.confirmation=no modify "$task_uuid" manual_priority:1
            fi
        elif [[ "$issue_status" == "In Review" ]]; then
            log "Issue status is In Review, adding +review tag"
            task rc.confirmation=no modify "$task_uuid" +review
        fi
    fi
}

# ====================================================
# PHASE 4: SYNCHRONIZATION OPERATIONS
# ====================================================

# Create a new task for an issue and annotate it
create_and_annotate_task() {
    local issue_description="$1"
    local issue_repo_name="$2"
    local issue_url="$3"
    local issue_number="$4"
    local project_name="$5"
    local issue_status="$6"
    
    log "Creating new task for issue: $issue_description"
    local task_uuid
    task_uuid=$(create_task "$issue_description" "+$issue_repo_name" "+fresh" "project:$project_name")
    
    if [[ -n "$task_uuid" ]]; then
        annotate_task "$task_uuid" "$issue_url"
        log "Task created and annotated for: $issue_description"
        task rc.confirmation=no modify "$task_uuid" linear_issue_id:"$issue_number"
        task rc.confirmation=no modify "$task_uuid" +todo
        
        # Manage project settings
        manage_project_settings "$task_uuid" "$project_name" "$issue_number"
        
        # Check task for special tags right after creation
        # This handles cases where tags might have been added via hooks
        update_task_status "$task_uuid" "$issue_status"
    else
        log "Error: Failed to create task for: $issue_description" >&2
    fi
}

# Synchronize a single issue with Taskwarrior
sync_to_taskwarrior() {
    local issue_line="$1"
    local issue_id issue_description issue_repo_name issue_url task_uuid issue_number project_name issue_status

    issue_id=$(echo "$issue_line" | jq -r '.id')
    issue_description=$(echo "$issue_line" | jq -r '.description')
    issue_repo_name=$(echo "$issue_line" | jq -r '.repository' | awk -F/ '{print $NF}')
    issue_url=$(echo "$issue_line" | jq -r '.html_url')
    issue_number=$(echo "$issue_line" | jq -r '.issue_id')
    project_name=$(echo "$issue_line" | jq -r '.project')
    issue_status=$(echo "$issue_line" | jq -r '.status')

    log "Processing Issue ID: $issue_id, Description: $issue_description"

    # First, try to find task by linear_issue_id if available
    local existing_task_uuid=""
    if [[ -n "$issue_number" ]]; then
        existing_task_uuid=$(task "linear_issue_id:$issue_number" status:pending export 2>/dev/null | jq -r '.[0].uuid' 2>/dev/null || echo "")
    fi

    # If not found by linear_issue_id, try by description
    if [[ -z "$existing_task_uuid" ]]; then
        existing_task_uuid=$(get_task_id_by_description "$issue_description")
    fi
    
    task_uuid="$existing_task_uuid"

    if [[ -z "$task_uuid" || "$task_uuid" == "null" ]]; then
        log "No valid existing task found - creating new task"
        create_and_annotate_task "$issue_description" "$issue_repo_name" "$issue_url" "$issue_number" "$project_name" "$issue_status"
    else
        # Fix any issues with newlines in task_uuid
        task_uuid=$(echo "$task_uuid" | tr -d '\n')
        log "Task already exists for: $issue_description (UUID: $task_uuid)"
        
        # Update task status based on current Linear issue status
        update_task_status "$task_uuid" "$issue_status"
    fi
}

# Synchronize all issues to Taskwarrior
sync_issues_to_taskwarrior() {
    local issues="$1"
    echo "$issues" | jq -c '.' | while IFS= read -r line; do
        sync_to_taskwarrior "$line"
    done
}

# ====================================================
# PHASE 5: CLEANUP AND MAINTENANCE
# ====================================================

# Compare existing Taskwarrior tasks with current issues and mark as completed if not present
compare_and_clean_tasks() {
    local issues_descriptions="$1"

    log "Starting comparison of Taskwarrior tasks and current issues."

    # OPTIMIZATION: Only get PENDING tasks with specific tags
    # This massively reduces the number of tasks to process
    local task_export
    task_export=$(task '+github or +linear or linear_issue_id.any:' '-triage' status:pending export)

    # Remove any empty or null entries (extra safety check)
    task_export=$(echo "$task_export" | jq -c '[.[] | select(.status == "pending")]')

    # Extract all issue descriptions into a temporary file for faster processing
    local issues_file
    issues_file=$(mktemp)
    echo "$issues_descriptions" | tr -d '\r' | grep -v '^$' | while IFS= read -r issue; do
        echo "${issue,,}" >>"$issues_file"
    done

    # Debug count
    local tasks_count
    tasks_count=$(echo "$task_export" | jq -r '.[] | .uuid' | wc -l)
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
                    task rc.confirmation=no "$task_uuid" delete
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

# Find tasks that have linear_issue_id but are no longer in our Linear feed
find_and_clean_reassigned_tasks() {
    local linear_issues="$1"
    
    log "Checking for reassigned Linear tasks..."

    # Get all tasks with linear_issue_id but exclude +triage tasks
    # OPTIMIZATION: Only get pending tasks
    local tasks_with_linear_id
    tasks_with_linear_id=$(task 'linear_issue_id.any:' '-triage' status:pending export)

    # Remove any empty or null entries (extra safety check)
    tasks_with_linear_id=$(echo "$tasks_with_linear_id" | jq -c '[.[] | select(.status == "pending")]')

    if [[ -z "$tasks_with_linear_id" || "$tasks_with_linear_id" == "[]" ]]; then
        log "No pending tasks with linear_issue_id found."
        return
    fi

    # Debug count
    local tasks_count
    tasks_count=$(echo "$tasks_with_linear_id" | jq -r '.[] | .uuid' | wc -l)
    log "Processing $tasks_count pending tasks with linear_issue_id"

    # Get all linear issue IDs from the Linear API response
    local all_linear_issue_ids
    all_linear_issue_ids=$(echo "$linear_issues" | jq -r '.issue_id // empty')

    # Process each task with a linear_issue_id
    echo "$tasks_with_linear_id" | jq -c '.[]' | while IFS= read -r task_data; do
        local status=$(echo "$task_data" | jq -r '.status')

        # Extra check - skip any non-pending tasks
        if [[ "$status" != "pending" ]]; then
            continue
        fi

        local linear_issue_id=$(echo "$task_data" | jq -r '.linear_issue_id')
        local task_uuid=$(echo "$task_data" | jq -r '.uuid')
        local task_description=$(echo "$task_data" | jq -r '.description')

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
                task rc.confirmation=no "$task_uuid" delete
            fi
        fi
    done
}

# Sync triage issues via systemd service
sync_triage_issues() {
    echo "Syncing triage issues"

    if systemctl --user start triage-sync.service; then
        log "Triage issues synced successfully"
    else
        log "Error: Failed to sync triage issues" >&2

    fi
}

# ====================================================
# PHASE 6: MAIN EXECUTION
# ====================================================

# Main function to orchestrate the synchronization
main() {
    # Phase 1: Environment and Setup
    log "Phase 1: Validating environment variables"
    validate_env_vars
    
    # Phase 2: Data Fetching
    log "Phase 2: Fetching issues from GitHub and Linear"
    local github_issues linear_issues
    github_issues=$(get_github_issues)
    linear_issues=$(get_linear_issues)

    if [[ -z "$github_issues" && -z "$linear_issues" ]]; then
        log "No issues retrieved from GitHub or Linear. Exiting."
        exit 0
    fi

    # Phase 3 & 4: Task Management & Synchronization
    log "Phase 3 & 4: Running synchronization operations"
    
    # Process specific deletion of reassigned Linear tasks
    [[ -n "$linear_issues" ]] && find_and_clean_reassigned_tasks "$linear_issues"

    # Normal sync process
    [[ -n "$github_issues" ]] && sync_issues_to_taskwarrior "$github_issues"
    [[ -n "$linear_issues" ]] && sync_issues_to_taskwarrior "$linear_issues"

    # Phase 5: Cleanup and Maintenance
    log "Phase 5: Performing cleanup and maintenance"
    
    # Compile all issue descriptions for the comparison
    local all_descriptions
    all_descriptions=$(
        echo "$github_issues" | jq -r '.description'
        echo "$linear_issues" | jq -r '.description'
    )
    
    # Run the comparison to mark tasks as completed or delete them
    compare_and_clean_tasks "$all_descriptions"
    
    # Sync triage issues as the final step
    sync_triage_issues
    
    log "Synchronization completed successfully"
}

# Execute the main function
main
