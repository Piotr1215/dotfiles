#!/usr/bin/env bash
set -eo pipefail

# Shared library for PR checkout operations
# Used by both TaskWarrior hooks and interactive scripts

checkout_pr_in_repo() {
    local org_repo="$1"  # Format: "org/repo" or just "repo" (assumes loft-sh)
    local pr_num="$2"
    local session_suffix="${3:-}"  # Optional suffix for tmux session name
    
    # Parse org and repo
    if [[ "$org_repo" == *"/"* ]]; then
        local org=$(echo "$org_repo" | cut -d"/" -f1)
        local repo=$(echo "$org_repo" | cut -d"/" -f2)
    else
        local org="loft-sh"
        local repo="$org_repo"
    fi
    
    local repo_path="/home/decoder/loft/$repo"
    
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
        if ! gh pr checkout "$pr_num" 2>/dev/null; then
            echo "Could not checkout PR #$pr_num (might be from a fork or closed)" >&2
        else
            echo "Successfully checked out PR #$pr_num" >&2
        fi
    fi
    
    # Create and switch to tmux session
    local session_name="${repo}${session_suffix}"
    if [ -n "$pr_num" ]; then
        session_name="${repo}-pr${pr_num}"
    fi
    
    # Create new tmux session (ignore if it already exists)
    tmux new-session -d -s "$session_name" -c "$repo_path" 2>/dev/null || true
    
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