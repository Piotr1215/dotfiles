#!/usr/bin/env bash

# __triage_issues_sync.sh
# Synchronizes Linear triage issues with Taskwarrior
# PROJECT: taskwarrior-sync

set -eo pipefail
source /home/decoder/dev/dotfiles/scripts/__lib_taskwarrior_interop.sh

# ====================================================
# PHASE 1: UTILITIES
# ====================================================

# Logger with timestamp
log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

# ====================================================
# PHASE 2: DATA FETCHING
# ====================================================

# Get all tasks with +triage tag
get_task_id_by_description() {
    local description="$1"
    task +triage status:pending export |
        jq -r --arg desc "$description" '.[] | select(.description == $desc) | .uuid'
}

# Get all triage tasks from Taskwarrior
get_all_triage_tasks() {
    task +triage status:pending export |
        jq -r '.[] | .description'
}

# Get all triage issues from Linear
get_triage_issues() {
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: $LINEAR_API_KEY" \
        --data '{"query": "query { issues(filter: {state: {name: {eq: \"Triage\"}}, team: {name: {in: [\"Docs\", \"Operations\"]}}}) { nodes { id identifier number title url team { name } } } }"}' \
        https://api.linear.app/graphql | jq -r '.data.issues.nodes[]'
}

# ====================================================
# PHASE 3: TASK MANAGEMENT
# ====================================================

# Create a new task for a triage issue
create_triage_task() {
    local issue_title="$1"
    local issue_id="$2"
    local issue_url="$3"
    local project="$4"
    local repo="$5"

    log "Creating new triage task for: $issue_title"
    local task_uuid
    task_uuid=$(create_task "$issue_title" "+triage" "$project" $repo "linear_issue_id:$issue_id") || true
    
    # Validate task UUID
    if [[ -z "$task_uuid" || "$task_uuid" == "null" ]]; then
        log "WARNING: Failed to create triage task - invalid task UUID returned"
        return ""
    fi
    
    annotate_task "$task_uuid" "$issue_url" || true
    echo "$task_uuid"
}

# Delete a task that's no longer in triage
delete_removed_task() {
    local task_desc="$1"
    local task_uuid
    
    task_uuid=$(get_task_id_by_description "$task_desc")
    if [[ -n "$task_uuid" && "$task_uuid" != "null" ]]; then
        log "Deleting task no longer in triage: $task_desc"
        echo "yes" | task "$task_uuid" delete
    else
        log "WARNING: Cannot delete task - invalid task UUID: '$task_uuid' for task: $task_desc"
    fi
}

# ====================================================
# PHASE 4: SYNCHRONIZATION
# ====================================================

# Delete tasks that are no longer in Linear triage
clean_removed_triage_tasks() {
    local linear_issues="$1"
    local task_desc
    
    log "Checking for tasks no longer in triage"
    while read -r task_desc; do
        if ! echo "$linear_issues" | grep -Fxq "$task_desc"; then
            delete_removed_task "$task_desc"
        fi
    done < <(get_all_triage_tasks)
}

# Add new triage issues to Taskwarrior
add_new_triage_issues() {
    local issue_title issue_id issue_url task_uuid team_name project
    local issues_added=0
    
    log "Adding new triage issues"
    while read -r issue; do
        issue_title=$(echo "$issue" | jq -r '.title')
        issue_id=$(echo "$issue" | jq -r '.identifier')
        issue_url=$(echo "$issue" | jq -r '.url')
        team_name=$(echo "$issue" | jq -r '.team.name')

        # Set project and repo based on team name
        if [ "$team_name" = "Operations" ]; then
            project="project:operations"
            repo=""
        else
            project="project:docs-maintenance"
            repo="repo:vcluster-docs"
        fi

        task_uuid=$(get_task_id_by_description "$issue_title")
        if [[ -z "$task_uuid" ]]; then
            task_uuid=$(create_triage_task "$issue_title" "$issue_id" "$issue_url" "$project" "$repo")
            issues_added=$((issues_added + 1))
        else
            log "Task already exists for: $issue_title"
        fi
    done < <(get_triage_issues | jq -c '.')
    
    log "Added $issues_added new triage issues"
    return 0
}

# ====================================================
# PHASE 5: MAIN EXECUTION
# ====================================================

main() {
    log "Starting triage issues sync"
    
    # Phase 2: Data Fetching
    log "Phase 2: Fetching triage issues from Linear"
    local linear_issues
    linear_issues=$(get_triage_issues | jq -r '.title')
    
    if [[ -z "$linear_issues" ]]; then
        log "No triage issues retrieved from Linear. Exiting."
        exit 0
    fi
    
    # Phase 3 & 4: Task Management & Synchronization
    log "Phase 3 & 4: Synchronizing triage issues"
    
    # First remove tasks no longer in triage
    clean_removed_triage_tasks "$linear_issues"
    
    # Then add new triage issues
    add_new_triage_issues
    
    log "Triage issues sync completed successfully"
}

# Execute the main function
main