#!/usr/bin/env bash
# PROJECT: taskwarrior-sync
# See: __lib_taskwarrior_interop.sh, ops-autonomous-worker.md, ops-triage-agent.md
# Related: task-resume-annotations (uses linear_issue_id for stable refs)
#
# Synchronizes Linear issues assigned to me with Taskwarrior.
#
# Key behaviors:
# 1. For unassigned Linear issues: Deletes them from Taskwarrior (since they're no longer relevant to you)
# 2. For completed Linear issues: Only marks as done if truly in a completed state
#    (Released, Canceled, Done, Ready for Release, Duplicate, Archived)
# 3. The +backlog tag is now Taskwarrior-internal and doesn't sync with Linear
#    (users can add/remove this tag manually without affecting Linear)
# 4. Linear Triage-status issues are EXCLUDED from sync entirely (see the guard
#    in sync_to_taskwarrior). Linear Triage is Piotr's own inbox gate: only
#    issues he accepts OUT of Triage count as assigned work. Triage-status
#    issues are never created, updated, or tagged here. They stay in the fetched
#    feed only so the cleanup passes do not delete an already-created task while
#    it is mid-transition; they simply are not synced as tasks.
#
# Note: The cross-team Triage feed was removed — only issues assigned to me sync.
# Note: GitHub issue sync was removed in v1.0-with-github-sync (no GitHub issues assigned)

# shellcheck disable=SC2155
source "$(dirname "${BASH_SOURCE[0]}")/__lib_taskwarrior_interop.sh"

set -eo pipefail

# Set new line and tab for word splitting
IFS=$'\n\t'

# Team prefix → project mapping (edit here when teams rename)
declare -A TEAM_PREFIX_PROJECT=(
    ["DOC"]="docs-maintenance"
    ["DEVOPS"]="operations"
    ["ENGAI"]="ai"
)
# Team prefix → repo mapping (only for teams that need repo set)
declare -A TEAM_PREFIX_REPO=(
    ["DOC"]="vcluster-docs"
)

# ====================================================
# LOGGING FUNCTIONS
# ====================================================

# Logger with timestamp
log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

# Strip emoji and symbol Unicode characters from descriptions to prevent matching failures
# Emojis in Linear issue titles cause grep -Fxq and jq string comparison to break,
# leading to duplicate task creation (e.g. DEVOPS-634 created 19 duplicates)
sanitize_description() {
    local desc="$1"
    # Remove 4-byte UTF-8 sequences (U+10000+: emoticons, flags, symbols)
    # Remove 3-byte emoji ranges:
    #   U+2300-23FF (misc technical: ⌚⏰), U+2600-27BF (symbols: ☀✅✨❌),
    #   U+2B00-2BFF (arrows/stars: ⭐⬆), U+FE00-FE0F (variation selectors)
    # Remove zero-width joiner (U+200D)
    # Then collapse whitespace and trim
    printf '%s' "$desc" | LC_ALL=C sed \
        -e 's/\xf0[\x80-\xbf][\x80-\xbf][\x80-\xbf]//g' \
        -e 's/\xe2[\x8c-\x8f][\x80-\xbf]//g' \
        -e 's/\xe2[\x98-\x9e][\x80-\xbf]//g' \
        -e 's/\xe2[\xac-\xaf][\x80-\xbf]//g' \
        -e 's/\xef\xb8[\x80-\x8f]//g' \
        -e 's/\xe2\x80\x8d//g' \
        -e 's/  */ /g' -e 's/^ //' -e 's/ $//'
}

# Function to trim leading and trailing whitespace (hardened against command injection)
trim_whitespace() {
    local input="$1"
    # Use parameter expansion instead of sed to avoid command injection
    input="${input#"${input%%[![:space:]]*}"}"  # Remove leading whitespace
    input="${input%"${input##*[![:space:]]}"}"  # Remove trailing whitespace
    echo "$input"
}

# Convert an ISO-8601 timestamp to a Unix epoch.
# Returns 0 for empty, "null", or unparseable input so callers can compare
# safely without tripping on missing watermarks (e.g. brand-new tasks).
#
# TaskWarrior `export` renders dates in basic-ISO UTC (YYYYMMDDTHHMMSSZ), which
# `date -d` cannot parse. Normalize that form to extended ISO (with the explicit
# Z) first so it is read as UTC, matching the Linear updatedAt side (already
# extended ISO with Z, possibly with a .NNN fraction). Canonicalizing both sides
# to UTC keeps the watermark comparison timezone-unambiguous.
ts_to_epoch() {
    local ts="$1"
    if [[ -z "$ts" || "$ts" == "null" ]]; then
        echo 0
        return
    fi
    if [[ "$ts" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$ ]]; then
        ts="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}T${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}Z"
    fi
    date -d "$ts" +%s 2>/dev/null || echo 0
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

# Retrieve and format Linear issues with enhanced error handling
get_linear_issues() {
    local response
    local exit_code
    local temp_response
    local max_retries=3
    local retry_count=0
    local wait_time=2

    # Create temporary file for response (with proper cleanup)
    if ! temp_response=$(mktemp); then
        echo "Error: Failed to create temporary file" >&2
        return 1
    fi

    # Ensure cleanup on exit
    trap "rm -f '$temp_response'" EXIT

    # Retry loop for API call
    while [[ $retry_count -lt $max_retries ]]; do
        # Make API call with explicit error handling and timeouts
        local curl_stderr
        curl_stderr=$(mktemp)
        trap "rm -f '$temp_response' '$curl_stderr'" EXIT

        response=$(curl -s -w "\n%{http_code}" \
            --connect-timeout 10 \
            --max-time 30 \
            -X POST \
            -H "Content-Type: application/json" \
            -H "Authorization: ${LINEAR_API_KEY}" \
            --data '{"query": "query { user(id: \"'"$LINEAR_USER_ID"'\") { id name assignedIssues(filter: { state: { name: { nin: [\"Released\", \"Canceled\",\"Done\",\"Ready for Release\",\"Duplicate\",\"Archived\"] } } }) { nodes { id title url state { name } project { name } dueDate priority updatedAt cycle { number } attachments { nodes { url } } } } } }"}' \
            https://api.linear.app/graphql 2>"$curl_stderr")
        exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            rm -f "$curl_stderr"
            break
        fi

        # Log error and retry if not last attempt
        local error_msg
        error_msg=$(cat "$curl_stderr" 2>/dev/null || echo "Unknown error")
        retry_count=$((retry_count + 1))

        if [[ $retry_count -lt $max_retries ]]; then
            echo "Warning: Linear API request failed (attempt $retry_count/$max_retries, curl exit code: $exit_code)" >&2
            echo "Details: $error_msg" >&2
            echo "Retrying in ${wait_time}s..." >&2
            sleep "$wait_time"
            wait_time=$((wait_time * 2))  # Exponential backoff
            rm -f "$curl_stderr"
        else
            echo "Error: Linear API request failed after $max_retries attempts (curl exit code: $exit_code)" >&2
            echo "Details: $error_msg" >&2
            rm -f "$temp_response" "$curl_stderr"
            return 1
        fi
    done
    
    local http_code=$(echo "$response" | tail -1)
    local content=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" -ne 200 ]]; then
        echo "Error: Linear API returned HTTP $http_code" >&2
        echo "Response: $content" >&2
        rm -f "$temp_response"
        return 1
    fi
    
    # Validate JSON response
    if ! echo "$content" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON response from Linear API" >&2
        echo "Response: $content" >&2
        rm -f "$temp_response"
        return 1
    fi
    
    # Check for API errors in the response
    local errors
    errors=$(echo "$content" | jq -r '.errors // empty')
    if [[ -n "$errors" ]]; then
        echo "Error: Linear API returned errors: $errors" >&2
        rm -f "$temp_response"
        return 1
    fi
    
    # Parse the issues with error handling
    local issues
    if ! issues=$(echo "$content" | jq -c '.data.user.assignedIssues.nodes[] | {
            id: .id,
            description: .title,
            repository: "linear",
            html_url: .url,
            issue_id: (.url | split("/") | .[-2]),
            project: .project.name,
            status: .state.name,
            due_date: .dueDate,
            priority: .priority,
            updated_at: .updatedAt,
            cycle_number: .cycle.number,
            pr_url: ([.attachments.nodes[]? | select(.url != null and (.url | test("github.com.*/pull/"))) | .url] | .[0] // null)
        }' 2>/dev/null); then
        echo "Error: Failed to parse Linear issues" >&2
        rm -f "$temp_response"
        return 1
    fi
    
    # Cleanup
    rm -f "$temp_response"
    
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
    if [[ "$status" =~ ^(Released|Canceled|Done|Ready\ for\ Release|Duplicate|Archived)$ ]]; then
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

        if echo "$formatted_project" | grep -qi 'vclustercloud-maintenance'; then
            task rc.confirmation=no modify "$task_uuid" repo:hosted-platform
        elif echo "$formatted_project" | grep -qi 'loft.rocks'; then
            task rc.confirmation=no modify "$task_uuid" repo:loft-prod
        elif echo "$formatted_project" | grep -qi 'vnode'; then
            task rc.confirmation=no modify "$task_uuid" repo:vnode-docs
        fi
    else
        # Use team prefix config for project assignment
        local prefix
        for prefix in "${!TEAM_PREFIX_PROJECT[@]}"; do
            if [[ "$issue_number" == "${prefix}-"* ]]; then
                task rc.confirmation=no modify "$task_uuid" project:"${TEAM_PREFIX_PROJECT[$prefix]}"
                break
            fi
        done
    fi

    # Set repo based on team prefix config
    local prefix
    for prefix in "${!TEAM_PREFIX_REPO[@]}"; do
        if [[ "$issue_number" == "${prefix}-"* ]]; then
            task rc.confirmation=no modify "$task_uuid" repo:"${TEAM_PREFIX_REPO[$prefix]}"
            break
        fi
    done
}

# Update task tags and priority based on Linear issue status
update_task_status() {
    local task_uuid="$1"
    local issue_status="$2"
    local issue_priority="$3"
    
    # Validate task UUID
    if [[ -z "$task_uuid" || "$task_uuid" == "null" ]]; then
        log "WARNING: Cannot update task status - invalid task UUID: '$task_uuid'"
        return
    fi
    
    # Check if task has +backlog or +review tags using task export JSON
    local task_json
    local has_backlog="false"
    local has_review="false"
    local has_fresh="false"

    # Use task export JSON for this specific task
    task_json=$(task "$task_uuid" export 2>/dev/null)

    # Check for special tags
    if [[ -n "$task_json" ]]; then
        has_backlog=$(echo "$task_json" | jq -r '.[0].tags | if . then contains(["backlog"]) else false end')
        has_review=$(echo "$task_json" | jq -r '.[0].tags | if . then contains(["review"]) else false end')
        has_fresh=$(echo "$task_json" | jq -r '.[0].tags | if . then contains(["fresh"]) else false end')
        log "Special tag check: has_backlog=$has_backlog, has_review=$has_review, has_fresh=$has_fresh"
    fi

    # Always sync status from Linear - Linear is the source of truth
    # No special handling for +backlog tag - it should be synced like other tags
    # Removed the special backlog handling - now syncing all statuses
    
    # Normal status sync logic from Linear
    if [[ "$issue_status" =~ [Bb]acklog || "$issue_status" == "Idea" ]]; then
        log "Issue status is Backlog/Idea, adding +backlog tag, removing +next and +hold tags"
        task rc.confirmation=no modify "$task_uuid" +backlog -next -hold
    elif [[ "$issue_status" == "Todo" || "$issue_status" == "In Progress" || "$issue_status" == "Investigating" ]]; then
        log "Issue status is Todo/In Progress/Investigating, removing +backlog and +hold tags"
        task rc.confirmation=no modify "$task_uuid" -backlog -hold
        # Remove fresh tag only when actual work starts (In Progress/Investigating), not Todo
        if [[ "$has_fresh" == "true" && "$issue_status" != "Todo" ]]; then
            log "Work has started (status=$issue_status), removing +fresh tag"
            task rc.confirmation=no modify "$task_uuid" -fresh
        fi
    elif [[ "$issue_status" == "In Review" ]]; then
        log "Issue status is In Review, adding +review tag and removing +backlog and +hold tags"
        task rc.confirmation=no modify "$task_uuid" +review -backlog -hold
        # Remove fresh tag when in review
        if [[ "$has_fresh" == "true" ]]; then
            log "Issue is in review, removing +fresh tag"
            task rc.confirmation=no modify "$task_uuid" -fresh
        fi
    elif [[ "$issue_status" == "Parked" ]]; then
        log "Issue status is Parked, adding +backlog and +hold tags"
        task rc.confirmation=no modify "$task_uuid" +backlog +hold
    fi
    
    # Manage +triage tag (exact match — must not collide with +triaged from auto-triage).
    # `contains(["triage"])` would also match "triaged" via substring, so use index.
    local has_triage=$(echo "$task_json" | jq -r '.[0].tags | if . then (index("triage") != null) else false end')
    if [[ "$issue_status" == "Triage" ]]; then
        if [[ "$has_triage" == "false" ]]; then
            log "Issue is in Triage state, adding +triage tag"
            task rc.confirmation=no modify "$task_uuid" +triage
        fi
    else
        if [[ "$has_triage" == "true" ]]; then
            log "Issue is no longer in Triage state, removing +triage tag"
            task rc.confirmation=no modify "$task_uuid" -triage
        fi
    fi
    
    # Update priority based on Linear priority (only for non-backlog/review tasks)
    if [[ -n "$issue_priority" && ("$issue_priority" == "1" || "$issue_priority" == "2") ]]; then
        # Check current priority
        local current_priority
        current_priority=$(task _get "$task_uuid".priority 2>/dev/null || echo "")
        if [[ "$current_priority" != "H" ]]; then
            log "Setting priority:H for High/Urgent Linear issue (priority=$issue_priority)"
            task rc.confirmation=no modify "$task_uuid" priority:H
        fi
    elif [[ -n "$issue_priority" && "$issue_priority" != "1" && "$issue_priority" != "2" ]]; then
        # Remove high priority if Linear priority changed
        local current_priority
        current_priority=$(task _get "$task_uuid".priority 2>/dev/null || echo "")
        if [[ "$current_priority" == "H" ]]; then
            log "Removing priority:H as Linear priority changed (priority=$issue_priority)"
            task rc.confirmation=no modify "$task_uuid" priority:
        fi
    fi
    
    # Check if the +review tag should be removed based on current Linear status.
    # +review has TWO meanings that must both be honored:
    #   1. Linear status == "In Review"  (set in the branch above), and
    #   2. the task has an attached GitHub PR (set by attach_pr_link).
    # Piotr's reports surface +review but hide the pr-reviews mirror tasks via
    # -pr, so +review is the glanceable "this task has an open PR" signal. A
    # Todo/In-Progress task with an open PR must therefore KEEP +review. Only
    # strip it when the issue is NOT In Review AND no /pull/ annotation exists.
    # Net invariant: +review present iff (status == In Review) OR (PR attached).
    if [[ "$has_review" == "true" && "$issue_status" != "In Review" ]]; then
        local has_pr_annotation
        has_pr_annotation=$(echo "$task_json" | jq -r '[.[0].annotations[]? | (.description // "") | select(test("github.com.*/pull/"))] | length > 0')
        if [[ "$has_pr_annotation" == "true" ]]; then
            log "Task has +review and status is '$issue_status' but a PR is attached - keeping +review (PR-glance signal)"
        else
            log "Task has +review tag but Linear status is '$issue_status' and no PR attached - removing +review tag"
            task rc.confirmation=no modify "$task_uuid" -review

            # Re-run the status update logic now that review tag is removed
            update_task_status "$task_uuid" "$issue_status" "$issue_priority"
        fi
    fi
}

# ====================================================
# PHASE 4: SYNCHRONIZATION OPERATIONS
# ====================================================

# Mirror a Linear-attached GitHub PR onto a task as an annotation, idempotently.
# Linear stores PRs as issue attachments (the same source linear.get-prs reads),
# but get_linear_issues historically never requested that connection, so a PR
# attached in Linear never landed on the task. We ride the annotation channel the
# +wt worktree hook already scans for /pull/ URLs (on-modify-worktree-linear-pr-
# handler.py), rather than a github_pr UDA: an undefined UDA would be mis-parsed
# into the task description. Re-running the sync must never duplicate the
# annotation, so skip when the exact URL is already present. Exact-match via
# jq index (not substring) avoids the +triage/+triaged style collision.
attach_pr_link() {
    local task_uuid="$1"
    local pr_url="$2"

    [[ -z "$pr_url" || "$pr_url" == "null" ]] && return 0
    [[ -z "$task_uuid" || "$task_uuid" == "null" ]] && return 0

    # Read the task once; drive both the +review glance-tag and the annotation.
    local task_json
    task_json=$(task "$task_uuid" export 2>/dev/null)

    # A PR is attached, so ensure the glanceable +review tag is present. Piotr's
    # reports surface +review while hiding the pr-reviews mirror tasks via -pr,
    # so +review (NOT +pr) is the correct "this task has an open PR" signal;
    # stamping +pr here would hide the task from report.current/backlog/byrepo/
    # byproject. Idempotent via jq index (exact element, not contains which is
    # substring in jq). Checked independently of the annotation below so an
    # already-synced task that carries the PR annotation but predates this gets
    # +review backfilled on the next sync. update_task_status keeps +review while
    # a /pull/ annotation exists, so this and the strip logic agree.
    local has_review_tag
    has_review_tag=$(echo "$task_json" | jq -r '.[0].tags | if . then (index("review") != null) else false end')
    if [[ "$has_review_tag" != "true" ]]; then
        log "Adding +review tag (PR attached, glanceable signal): $pr_url"
        task rc.confirmation=no modify "$task_uuid" +review
    fi

    # Mirror the PR URL as an annotation (the channel the +wt worktree hook
    # scans for /pull/ URLs). Idempotent: skip when the exact URL is already
    # present. Exact-match via jq index (not substring) avoids collisions.
    local has_pr
    has_pr=$(echo "$task_json" \
        | jq -r --arg u "$pr_url" '.[0].annotations // [] | map(.description) | index($u) != null')
    if [[ "$has_pr" == "true" ]]; then
        return 0
    fi

    log "Attaching PR link annotation: $pr_url"
    annotate_task "$task_uuid" "$pr_url"
}

# Create a new task for an issue and annotate it
create_and_annotate_task() {
    local issue_description="$1"
    local issue_repo_name="$2"
    local issue_url="$3"
    local issue_number="$4"
    local project_name="$5"
    local issue_status="$6"
    local issue_due_date="$7"
    local issue_priority="$8"
    local cycle_number="$9"
    local issue_updated_at="${10}"
    local issue_pr_url="${11}"

    log "Creating new task for issue: $issue_description"
    
    # Determine if fresh tag should be added based on status
    # Fresh tag should be added for statuses where work hasn't started yet
    local fresh_tag=""
    if [[ ! "$issue_status" =~ ^(In\ Progress|Investigating|In\ Review)$ ]]; then
        fresh_tag="+fresh"
    fi
    
    local task_uuid
    # Don't add +linear tag - it's redundant with linear_issue_id field
    local repo_tag=""
    [[ "$issue_repo_name" != "linear" ]] && repo_tag="+$issue_repo_name"
    task_uuid=$(create_task "$issue_description" $repo_tag $fresh_tag "project:$project_name")
    
    if [[ -n "$task_uuid" ]]; then
        annotate_task "$task_uuid" "$issue_url"
        attach_pr_link "$task_uuid" "$issue_pr_url"
        log "Task created and annotated for: $issue_description"
        task rc.confirmation=no modify "$task_uuid" linear_issue_id:"$issue_number"
        
        # Manage project settings
        manage_project_settings "$task_uuid" "$project_name" "$issue_number"
        
        # Check task for special tags right after creation
        # This handles cases where tags might have been added via hooks
        update_task_status "$task_uuid" "$issue_status" "$issue_priority"
        
        # Set due date if present
        if [[ -n "$issue_due_date" && "$issue_due_date" != "null" ]]; then
            log "Setting due date to: $issue_due_date"
            task rc.confirmation=no modify "$task_uuid" due:"$issue_due_date"
        fi
        
        # Set priority:H for High or Urgent Linear issues
        if [[ -n "$issue_priority" && ("$issue_priority" == "1" || "$issue_priority" == "2") ]]; then
            log "Setting priority:H for High/Urgent Linear issue (priority=$issue_priority)"
            task rc.confirmation=no modify "$task_uuid" priority:H
        fi

        # Set cycle UDA if cycle number exists
        if [[ -n "$cycle_number" && "$cycle_number" != "null" ]]; then
            log "Setting cycle:$cycle_number"
            task rc.confirmation=no modify "$task_uuid" cycle:"$cycle_number"
        fi

        # Seed the new_activity watermark with the current Linear updatedAt.
        # No +updated tag: this is the initial baseline, not a re-surface signal.
        if [[ -n "$issue_updated_at" && "$issue_updated_at" != "null" ]]; then
            log "Seeding new_activity watermark to $issue_updated_at"
            task rc.confirmation=no modify "$task_uuid" new_activity:"$issue_updated_at"
        fi
    else
        log "Error: Failed to create task for: $issue_description" >&2
    fi
}

# Synchronize a single issue with Taskwarrior
sync_to_taskwarrior() {
    local issue_line="$1"
    local issue_id issue_description issue_repo_name issue_url task_uuid issue_number project_name issue_status issue_due_date issue_priority cycle_number issue_updated_at pr_url

    issue_id=$(echo "$issue_line" | jq -r '.id')
    issue_description=$(echo "$issue_line" | jq -r '.description')
    issue_description=$(sanitize_description "$issue_description")
    issue_repo_name=$(echo "$issue_line" | jq -r '.repository' | awk -F/ '{print $NF}')
    issue_url=$(echo "$issue_line" | jq -r '.html_url')
    issue_number=$(echo "$issue_line" | jq -r '.issue_id')
    project_name=$(echo "$issue_line" | jq -r '.project')
    issue_status=$(echo "$issue_line" | jq -r '.status')
    issue_due_date=$(echo "$issue_line" | jq -r '.due_date // empty')
    issue_priority=$(echo "$issue_line" | jq -r '.priority // empty')
    cycle_number=$(echo "$issue_line" | jq -r '.cycle_number // empty')
    # Strip fractional seconds (.NNN) but keep the trailing Z. TaskWarrior's
    # date parser ignores the Z when a fraction is present and stores the
    # wall-clock as LOCAL time, shifting the watermark by the UTC offset (e.g.
    # -2h in Europe/Berlin) so every already-triaged issue compares "newer" and
    # is perpetually re-flagged +updated. Writing the second-precision UTC form
    # makes TaskWarrior store the correct instant. This single point feeds all
    # three write sites (new-task seed, silent-seed, bump).
    issue_updated_at=$(echo "$issue_line" | jq -r '.updated_at // empty' | sed -E 's/\.[0-9]+Z$/Z/')
    # First github.com/.../pull/ URL among the Linear issue's attachments, if any.
    pr_url=$(echo "$issue_line" | jq -r '.pr_url // empty')

    log "Processing Issue ID: $issue_id, Description: $issue_description"

    # NEVER sync a Linear issue still in Triage status. A Triage-status issue is
    # not yet real work: it must never become a Taskwarrior task, never be
    # auto-batched, and never be triaged/dispatched by the triage agent (Gordon).
    # It STAYS in the fetched feed (get_linear_issues does not exclude it), so the
    # cleanup passes still see it and do NOT delete an already-created task; we
    # only skip create/update here while it sits in Triage. When it moves to a
    # real status (Todo/In Progress/In Review/etc.) it syncs normally next run.
    if [[ "$issue_status" == "Triage" ]]; then
        log "Issue $issue_number is in Triage status - excluding from sync (not created, not updated, not triaged)"
        return 0
    fi

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
        create_and_annotate_task "$issue_description" "$issue_repo_name" "$issue_url" "$issue_number" "$project_name" "$issue_status" "$issue_due_date" "$issue_priority" "$cycle_number" "$issue_updated_at" "$pr_url"
    else
        # Fix any issues with newlines in task_uuid
        task_uuid=$(echo "$task_uuid" | tr -d '\n')
        log "Task already exists for: $issue_description (UUID: $task_uuid)"
        
        # Check if task should have fresh tag but doesn't
        local task_json
        task_json=$(task "$task_uuid" export 2>/dev/null)
        if [[ -n "$task_json" ]]; then
            local has_fresh=$(echo "$task_json" | jq -r '.[0].tags | if . then contains(["fresh"]) else false end')
            local has_started=$(echo "$task_json" | jq -r '.[0].tags | if . then contains(["started"]) else false end')
            local has_review=$(echo "$task_json" | jq -r '.[0].tags | if . then contains(["review"]) else false end')
            local has_start_time=$(echo "$task_json" | jq -r '.[0].start // empty')
            
            # Remove fresh tag if task has review tag (they are mutually exclusive)
            if [[ "$has_fresh" == "true" && "$has_review" == "true" ]]; then
                log "Task has both +fresh and +review tags - removing +fresh tag (mutually exclusive)"
                task rc.confirmation=no modify "$task_uuid" -fresh
            # Add fresh tag if:
            # - Task doesn't have fresh tag
            # - Task doesn't have started tag
            # - Task doesn't have review tag (mutually exclusive)
            # - Task has never been started (no start time in history)
            # - Issue status indicates work hasn't actually started (Todo is still fresh)
            elif [[ "$has_fresh" == "false" && "$has_started" == "false" && "$has_review" == "false" && -z "$has_start_time" ]] && \
               [[ ! "$issue_status" =~ ^(In\ Progress|Investigating|In\ Review)$ ]]; then
                log "Adding missing +fresh tag to existing task"
                task rc.confirmation=no modify "$task_uuid" +fresh
            fi
        fi
        
        # Update task status based on current Linear issue status
        update_task_status "$task_uuid" "$issue_status" "$issue_priority"

        # Backfill the Linear-attached PR onto already-synced tasks (idempotent).
        attach_pr_link "$task_uuid" "$pr_url"

        # Re-surface the issue when Linear shows newer activity than our watermark.
        # new_activity stores the last-seen Linear updatedAt.
        #
        # First contact (empty stored watermark): seed it silently with no +updated.
        # An empty watermark is not a real "0" baseline. Every existing task would
        # otherwise compare real-updatedAt > empty and get flagged at once (first-run
        # flood). Seeding silently matches the new-task seeding behavior.
        #
        # Genuine change (stored watermark non-empty AND issue_updated_at strictly
        # newer): bump the watermark and mark the task +updated so triage re-looks.
        # A +fresh task is already queued for auto-batch, so it needs no +updated.
        if [[ -n "$issue_updated_at" && "$issue_updated_at" != "null" ]]; then
            local stored_activity stored_epoch updated_epoch has_fresh_tag
            # Read the watermark from export, not `_get`. `_get` renders the
            # stored instant as a timezone-naive local wall clock (no Z), which
            # `ts_to_epoch` would then compare against the explicit-UTC Linear
            # side and skew by the local offset, re-flagging every issue every
            # run. Export renders it as explicit-UTC basic-ISO (YYYYMMDDTHHMMSSZ),
            # which ts_to_epoch normalizes to a UTC epoch.
            stored_activity=$(task "$task_uuid" export 2>/dev/null | jq -r '.[0].new_activity // empty')
            if [[ -z "$stored_activity" || "$stored_activity" == "null" ]]; then
                log "No new_activity watermark yet, seeding silently to $issue_updated_at (no +updated)"
                task rc.confirmation=no modify "$task_uuid" new_activity:"$issue_updated_at"
            else
                stored_epoch=$(ts_to_epoch "$stored_activity")
                updated_epoch=$(ts_to_epoch "$issue_updated_at")
                if [[ "$updated_epoch" -gt "$stored_epoch" ]]; then
                    log "Linear activity is newer than watermark (was: $stored_activity), bumping new_activity to $issue_updated_at"
                    task rc.confirmation=no modify "$task_uuid" new_activity:"$issue_updated_at"
                    has_fresh_tag=$(task "$task_uuid" export 2>/dev/null | jq -r '.[0].tags | if . then contains(["fresh"]) else false end')
                    if [[ "$has_fresh_tag" != "true" ]]; then
                        log "Task is past fresh, adding +updated to re-surface for triage"
                        task rc.confirmation=no modify "$task_uuid" +updated
                    fi
                fi
            fi
        fi

        # Update due date
        if [[ -n "$issue_due_date" && "$issue_due_date" != "null" ]]; then
            log "Setting due date to: $issue_due_date"
            task rc.confirmation=no modify "$task_uuid" due:"$issue_due_date"
        elif [[ "$issue_due_date" == "null" || -z "$issue_due_date" ]]; then
            # Check if task currently has a due date
            local current_due
            current_due=$(task _get "$task_uuid".due 2>/dev/null || echo "")
            if [[ -n "$current_due" ]]; then
                log "Removing due date (was: $current_due)"
                task rc.confirmation=no modify "$task_uuid" due:
            fi
        fi

        # Update cycle UDA
        if [[ -n "$cycle_number" && "$cycle_number" != "null" ]]; then
            # Check if cycle needs updating
            local current_cycle
            current_cycle=$(task _get "$task_uuid".cycle 2>/dev/null || echo "")
            if [[ "$current_cycle" != "$cycle_number" ]]; then
                log "Updating cycle to: $cycle_number (was: $current_cycle)"
                task rc.confirmation=no modify "$task_uuid" cycle:"$cycle_number"
            fi
        elif [[ "$cycle_number" == "null" || -z "$cycle_number" ]]; then
            # Check if task currently has a cycle
            local current_cycle
            current_cycle=$(task _get "$task_uuid".cycle 2>/dev/null || echo "")
            if [[ -n "$current_cycle" ]]; then
                log "Removing cycle (was: $current_cycle)"
                task rc.confirmation=no modify "$task_uuid" cycle:
            fi
        fi
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

    # OPTIMIZATION: Only get PENDING tasks with Linear issue IDs
    # This massively reduces the number of tasks to process
    local task_export
    task_export=$(task 'linear_issue_id.any:' status:pending export)

    # Remove any empty or null entries (extra safety check)
    task_export=$(echo "$task_export" | jq -c '[.[] | select(.status == "pending")]')

    # Extract all issue descriptions into a temporary file for faster processing
    local issues_file
    local cleanup_needed=false
    
    if ! issues_file=$(mktemp); then
        echo "Error: Failed to create temporary file" >&2
        return 1
    fi
    cleanup_needed=true

    # Ensure cleanup on ALL exit paths
    trap 'if [[ "$cleanup_needed" == true ]]; then rm -f "$issues_file"; fi' EXIT ERR
    
    echo "$issues_descriptions" | tr -d '\r' | grep -v '^$' | while IFS= read -r issue; do
        echo "$(sanitize_description "${issue,,}")" >>"$issues_file"
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
        local lower_desc=$(sanitize_description "${trimmed_desc,,}")
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

    # Clean up temp file
    rm -f "$issues_file"
    cleanup_needed=false

    log "Comparison of Taskwarrior tasks and issues completed."
}

# Find tasks that have linear_issue_id but are no longer in our Linear feed
find_and_clean_reassigned_tasks() {
    local linear_issues="$1"
    
    log "Checking for reassigned Linear tasks..."

    # OPTIMIZATION: Only get pending tasks with linear_issue_id
    local tasks_with_linear_id
    tasks_with_linear_id=$(task 'linear_issue_id.any:' status:pending export)

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

# ====================================================
# PHASE 6: MAIN EXECUTION
# ====================================================

# Main function to orchestrate the synchronization
main() {
    # Phase 1: Environment and Setup
    log "Phase 1: Validating environment variables"
    validate_env_vars

    # Phase 2: Data Fetching
    log "Phase 2: Fetching issues from Linear"
    local linear_issues
    linear_issues=$(get_linear_issues)

    if [[ -z "$linear_issues" ]]; then
        log "No issues retrieved from Linear. Exiting."
        exit 0
    fi

    # Phase 3 & 4: Task Management & Synchronization
    log "Phase 3 & 4: Running synchronization operations"

    find_and_clean_reassigned_tasks "$linear_issues"
    sync_issues_to_taskwarrior "$linear_issues"

    # Phase 5: Cleanup and Maintenance
    log "Phase 5: Performing cleanup and maintenance"

    local all_descriptions
    all_descriptions=$(echo "$linear_issues" | jq -r '.description' 2>/dev/null)

    compare_and_clean_tasks "$all_descriptions"

    log "Synchronization completed successfully"

    # Notify triage agent (both manual and cron invocations).
    # Previously this lived only in __sync_with_notify.sh, so manual runs
    # of this script never produced a nudge — see triage thread 2026-05-12.
    if [[ -x "$HOME/.claude/scripts/__auto_triage_nudge.sh" ]]; then
        log "Triggering auto-triage nudge"
        "$HOME/.claude/scripts/__auto_triage_nudge.sh" || log "WARN: auto-triage nudge failed (continuing)"
    fi
}

# Execute the main function
main
