#!/usr/bin/env bash
set -eo pipefail

# Shared library for PR checkout operations
# Used by both TaskWarrior hooks and interactive scripts

checkout_pr_in_repo() {
    local org_repo="$1"  # Format: "org/repo" or just "repo" (assumes loft-sh)
    local pr_num="$2"
    local session_suffix="${3:-}"  # Optional suffix for tmux session name
    local linear_id="${4:-}"  # Optional linear issue ID (e.g., DOC-1138)

    # Parse org and repo
    if [[ "$org_repo" == *"/"* ]]; then
        local org=$(echo "$org_repo" | cut -d"/" -f1)
        local repo=$(echo "$org_repo" | cut -d"/" -f2)
    else
        local org="loft-sh"
        local repo="$org_repo"
    fi

    local repo_path="/home/decoder/loft/$repo"
    local stashed=false
    local pr_checkout_success=false
    local worktree_path=""

    # Check for existing worktree if linear_id is provided
    if [ -n "$linear_id" ]; then
        local linear_lower=$(echo "$linear_id" | tr '[:upper:]' '[:lower:]')
        local worktree_dir="/home/decoder/dev/claude-wt-worktrees"
        # Find worktree matching the linear ID pattern (e.g., doc-1138-*)
        worktree_path=$(find "$worktree_dir" -maxdepth 1 -type d -name "${linear_lower}-*" 2>/dev/null | head -1)
        if [ -n "$worktree_path" ] && [ -d "$worktree_path" ]; then
            echo "Found existing worktree for $linear_id at $worktree_path" >&2
            repo_path="$worktree_path"
        fi
    fi
    
    # Skip clone/fetch/checkout if using existing worktree
    if [ -n "$worktree_path" ]; then
        echo "Using existing worktree, skipping git operations" >&2
    else
        # Clone or fetch the repository
        if [ ! -d "$repo_path" ]; then
            echo "Cloning $org/$repo..." >&2
            mkdir -p "$(dirname "$repo_path")"
            gh repo clone "$org/$repo" "$repo_path"
        else
            echo "Repository exists, checking status..." >&2

            # Check for uncommitted changes
            if git -C "$repo_path" status --porcelain | grep -q .; then
                echo "Repository has uncommitted changes, stashing..." >&2
                git -C "$repo_path" stash push -m "Auto-stash before PR $pr_num checkout"
                stashed=true
            fi

            echo "Fetching latest changes..." >&2
            git -C "$repo_path" fetch origin --prune

            # Try to checkout main/master branch first
            if git -C "$repo_path" rev-parse --verify origin/main >/dev/null 2>&1; then
                git -C "$repo_path" checkout main >/dev/null 2>&1 || true
                git -C "$repo_path" pull origin main --ff-only >/dev/null 2>&1 || true
            elif git -C "$repo_path" rev-parse --verify origin/master >/dev/null 2>&1; then
                git -C "$repo_path" checkout master >/dev/null 2>&1 || true
                git -C "$repo_path" pull origin master --ff-only >/dev/null 2>&1 || true
            fi
        fi

        # Checkout the PR if provided
        if [ -n "$pr_num" ]; then
            echo "Checking out PR #$pr_num..." >&2
            cd "$repo_path"
            if gh pr checkout "$pr_num" 2>/dev/null; then
                echo "Successfully checked out PR #$pr_num" >&2
                pr_checkout_success=true
            else
                echo "Could not checkout PR #$pr_num (might be from a fork or closed)" >&2
            fi
        fi
    fi
    
    # Create and switch to tmux session
    local session_name="${repo}${session_suffix}"
    if [ -n "$worktree_path" ] && [ -n "$linear_id" ]; then
        # Use linear ID for worktree sessions
        session_name="${repo}-${linear_id}"
    elif [ -n "$pr_num" ]; then
        session_name="${repo}-pr${pr_num}"
    fi
    
    # Create new tmux session (ignore if it already exists)
    tmux new-session -d -s "$session_name" -c "$repo_path" 2>/dev/null || true
    
    # Send notification if stashing occurred
    if [ "$stashed" = true ]; then
        if [ -n "$pr_num" ]; then
            tmux send-keys -t "$session_name" "echo '⚠️  Auto-stashed uncommitted changes before PR #$pr_num checkout'" C-m
        else
            tmux send-keys -t "$session_name" "echo '⚠️  Auto-stashed uncommitted changes'" C-m
        fi
    fi
    
    # Try to switch client, or attach if not in tmux
    if [ -n "$TMUX" ]; then
        tmux switch-client -t "$session_name"
    else
        tmux attach-session -t "$session_name"
    fi
    
    echo "$session_name"  # Return the session name
}

# Export the function if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f checkout_pr_in_repo
fi