#!/usr/bin/env bash
# PROJECT: agent-lifecycle
# PR Session Reaper - cleans up tmux sessions and worktrees for merged PRs
#
# SAFETY: Only touches sessions that are:
#   1. Registered in DuckDB agents table (agent-created)
#   2. Have a PR URL in TaskWarrior annotations
#   3. PR is in MERGED state
#   4. Worktree is clean (no uncommitted changes)
#
# Run via cron every 5 minutes
set -eo pipefail

NATS_URL="${NATS_URL:-nats://192.168.178.93:4222}"
LOG_FILE="${HOME}/.claude/logs/reaper.log"
DB_PATH="${AGENTS_DB_PATH:-/home/decoder/.claude/data/agents.duckdb}"
DRY_RUN="${DRY_RUN:-false}"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

notify_triage() {
    local event="$1"
    local payload="$2"
    nats pub -s "$NATS_URL" "triage.reap.$event" "$payload" 2>/dev/null || true
}

# Get agent sessions from DuckDB (authoritative source)
# Returns: agent_name|stable_pane (format: session:window.pane)
get_agent_sessions() {
    [[ ! -f "$DB_PATH" ]] && return
    duckdb "$DB_PATH" -noheader -list -separator '|' \
        -c "SELECT name, stable_pane FROM agents WHERE stable_pane IS NOT NULL;" 2>/dev/null || true
}

# Extract Linear ID from agent name (e.g., DOC-1201, DEVOPS-522)
extract_linear_id() {
    local name="$1"
    echo "$name" | grep -oE '[A-Z]+-[0-9]+' | tail -1 || echo ""
}

# Get ALL PR URLs from TaskWarrior for a Linear issue (one per line)
get_pr_urls_for_linear_id() {
    local linear_id="$1"
    [[ -z "$linear_id" ]] && return

    # Find task with this Linear ID and ALL pr-url annotations
    task linear_issue_id:"$linear_id" status:pending export 2>/dev/null | jq -r '
        .[0].annotations // [] |
        .[] |
        select(.description | startswith("pr-url:")) |
        .description | sub("pr-url:"; "")
    '
}

# Check if ALL PRs for an agent are merged
all_prs_merged() {
    local linear_id="$1"
    local pr_urls
    pr_urls=$(get_pr_urls_for_linear_id "$linear_id")

    [[ -z "$pr_urls" ]] && return 1  # No PRs = not ready to reap

    local total=0
    local merged=0

    while IFS= read -r pr_url; do
        [[ -z "$pr_url" ]] && continue
        ((total++))

        local state
        state=$(gh pr view "$pr_url" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")

        if [[ "$state" == "MERGED" ]]; then
            ((merged++))
        fi
    done <<< "$pr_urls"

    # All PRs must be merged
    [[ $total -gt 0 && $total -eq $merged ]]
}


# Get worktree path from tmux session
get_worktree_path() {
    local session="$1"
    tmux display-message -t "$session" -p '#{pane_current_path}' 2>/dev/null || echo ""
}

# Check if worktree has uncommitted changes
is_worktree_dirty() {
    local path="$1"
    [[ -d "$path" ]] || return 1
    [[ -n $(git -C "$path" status --porcelain 2>/dev/null) ]]
}

# Check if path is a git worktree (not the main repo)
is_git_worktree() {
    local path="$1"
    [[ -d "$path" ]] || return 1
    local git_dir
    git_dir=$(git -C "$path" rev-parse --git-dir 2>/dev/null || echo "")
    [[ "$git_dir" == *".git/worktrees/"* ]]
}

# Main reaper logic
reap_merged_sessions() {
    local reaped=0
    local blocked=0
    local skipped=0

    while IFS='|' read -r agent_name stable_pane; do
        [[ -z "$agent_name" || -z "$stable_pane" ]] && continue

        # Extract session name from stable_pane (format: session:window.pane)
        local session="${stable_pane%%:*}"
        [[ -z "$session" ]] && continue

        # SAFETY: Verify tmux session exists AND matches expected name
        if ! tmux has-session -t "$session" 2>/dev/null; then
            log "SKIP $agent_name: tmux session '$session' not found"
            ((skipped++))
            continue
        fi

        # Extract Linear ID to find PR
        local linear_id
        linear_id=$(extract_linear_id "$agent_name")
        if [[ -z "$linear_id" ]]; then
            log "SKIP $agent_name: no Linear ID found in name"
            ((skipped++))
            continue
        fi

        # Check if ALL PRs for this agent are merged
        if ! all_prs_merged "$linear_id"; then
            local pr_count
            pr_count=$(get_pr_urls_for_linear_id "$linear_id" | wc -l)
            if [[ $pr_count -eq 0 ]]; then
                log "SKIP $agent_name: no pr-url annotations for $linear_id"
            else
                log "SKIP $agent_name: not all PRs merged yet ($pr_count PRs)"
            fi
            ((skipped++))
            continue
        fi

        # All PRs merged - get list for notification
        local pr_urls
        pr_urls=$(get_pr_urls_for_linear_id "$linear_id" | tr '\n' ' ')

        # PR is merged - check worktree before cleanup
        local worktree
        worktree=$(get_worktree_path "$session")

        if [[ -n "$worktree" && -d "$worktree" ]]; then
            # SAFETY: Check for uncommitted changes
            if is_worktree_dirty "$worktree"; then
                log "BLOCKED $agent_name: dirty worktree at $worktree"
                notify_triage "blocked" "{\"agent\":\"$agent_name\",\"session\":\"$session\",\"reason\":\"dirty worktree\",\"path\":\"$worktree\",\"pr\":\"$pr_url\"}"
                ((blocked++))
                continue
            fi

            # Safe to reap
            if [[ "$DRY_RUN" == "true" ]]; then
                log "DRY-RUN would reap: $agent_name session=$session worktree=$worktree"
            else
                log "REAP $agent_name: PR merged, worktree clean"

                # Kill tmux session
                tmux kill-session -t "$session" 2>/dev/null || true

                # Remove worktree if it's actually a worktree (not main repo)
                if is_git_worktree "$worktree"; then
                    local main_repo
                    main_repo=$(git -C "$worktree" rev-parse --git-common-dir 2>/dev/null | sed 's|/.git$||' || echo "")
                    if [[ -n "$main_repo" && -d "$main_repo" ]]; then
                        git -C "$main_repo" worktree remove "$worktree" --force 2>/dev/null || true
                        # Prune remote tracking branches
                        git -C "$main_repo" fetch --prune 2>/dev/null || true
                    fi
                fi

                notify_triage "success" "{\"agent\":\"$agent_name\",\"session\":\"$session\",\"prs\":\"$pr_urls\"}"
                ((reaped++))
            fi
        else
            # No worktree - just kill session
            if [[ "$DRY_RUN" == "true" ]]; then
                log "DRY-RUN would kill: $agent_name session=$session (no worktree)"
            else
                log "REAP $agent_name: PR merged, no worktree"
                tmux kill-session -t "$session" 2>/dev/null || true
                notify_triage "success" "{\"agent\":\"$agent_name\",\"session\":\"$session\",\"prs\":\"$pr_urls\"}"
                ((reaped++))
            fi
        fi
    done < <(get_agent_sessions)

    # Summary
    if [[ $reaped -gt 0 || $blocked -gt 0 ]]; then
        log "SUMMARY: reaped=$reaped blocked=$blocked skipped=$skipped"
    fi
}

# Run
reap_merged_sessions
