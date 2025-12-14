#!/usr/bin/env bash

# __linear_issue_viewer.sh
# Simple Linear issue viewer with fzf-tmux for OPS, DOC, and IT projects
# 
# Usage: ./__linear_issue_viewer.sh
# Keybindings:
#   Enter - Open issue in browser
#   Ctrl+Y - Copy issue URL to clipboard

set -eo pipefail
IFS=$'\n\t'

# Source .envrc if running from autokey or other environments without LINEAR vars
if [[ -z "${LINEAR_API_KEY}" ]] && [[ -f ~/.envrc ]]; then
    source ~/.envrc
fi

# Validate necessary environment variables
validate_env_vars() {
    local required_vars=(LINEAR_API_KEY LINEAR_OPS_TEAM_ID LINEAR_DOCS_TEAM_ID LINEAR_IT_TEAM_ID)
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "Error: Environment variable $var is not set." >&2
            exit 1
        fi
    done
}

# Fetch issues from Linear for OPS, DOC, and IT teams
fetch_linear_issues() {
    local query='query {
        issues(
            first: 200
            filter: {
                state: { name: { nin: ["Released", "Closed", "Canceled", "Done"] } }
                team: { id: { in: ["'"$LINEAR_OPS_TEAM_ID"'", "'"$LINEAR_DOCS_TEAM_ID"'", "'"$LINEAR_IT_TEAM_ID"'"] } }
            }
            orderBy: updatedAt
        ) {
            nodes {
                identifier
                title
                url
                state { name }
                team { key }
                assignee { name }
                priority
                updatedAt
            }
        }
    }'
    
    # Make API call
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: $LINEAR_API_KEY" \
        --data "$(jq -n --arg query "$query" '{query: $query}')" \
        https://api.linear.app/graphql)
    
    # Check for errors
    if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
        echo "Error fetching issues from Linear:" >&2
        echo "$response" | jq '.errors' >&2
        exit 1
    fi
    
    echo "$response"
}

# Format issues for fzf display
format_issues() {
    local json_data="$1"
    
    # Parse and format issues
    echo "$json_data" | jq -r '.data.issues.nodes[] | 
        # Priority emoji
        (.priority as $p |
            if $p == 1 then "🔴"
            elif $p == 2 then "🟠"
            elif $p == 3 then "🟡"
            elif $p == 4 then "🔵"
            else "⚪"
            end
        ) + " " +
        # Team with padding
        (.team.key | . + " " * (4 - length)) + " " +
        # Identifier with padding
        (.identifier | . + " " * (10 - length)) + " " +
        # State with padding
        (.state.name | . + " " * (12 - length)) + " " +
        # Assignee or unassigned
        (if .assignee.name then .assignee.name else "Unassigned" end | .[0:15] | . + " " * (15 - length)) + " " +
        # Title (truncated)
        (.title | .[0:60]) +
        # Hidden URL for extraction
        " |URL:" + .url'
}

# Main function
main() {
    validate_env_vars
    
    echo "Fetching Linear issues from OPS, DOC, and IT teams..." >&2
    
    # Fetch issues
    local issues_json=$(fetch_linear_issues)
    
    # Format issues for display
    local formatted_issues=$(format_issues "$issues_json")
    
    if [[ -z "$formatted_issues" ]]; then
        echo "No issues found." >&2
        read -p "Press Enter to exit..."
        exit 0
    fi
    
    # Count issues
    local issue_count=$(echo "$formatted_issues" | wc -l)
    
    # Use plain fzf when already in a tmux popup
    local selected=$(echo "$formatted_issues" | fzf \
        --header "Linear Issues ($issue_count) | Enter: Open in browser | Ctrl+Y: Copy URL | Ctrl+C: Cancel" \
        --prompt "Search issues> " \
        --preview-window="hidden" \
        --bind "ctrl-c:abort" \
        --expect=ctrl-y)
    
    # Parse output - first line is the key pressed, second is selection
    local key=$(echo "$selected" | head -1)
    local selection=$(echo "$selected" | tail -n +2)
    
    if [[ -n "$selection" ]]; then
        # Extract URL from selection
        local url=$(echo "$selection" | sed -n 's/.*|URL:\(.*\)$/\1/p')
        
        if [[ "$key" == "ctrl-y" ]]; then
            # Copy URL to clipboard
            echo -n "$url" | xclip -selection clipboard
            echo "✓ Copied issue URL to clipboard: $url" >&2
        else
            # Open in browser (default action)
            echo "Opening: $url" >&2
            # Use tmux run-shell like the link runner does
            tmux run-shell "xdg-open '$url' && wmctrl -a Firefox"
        fi
    fi
}

# Output tab-separated data for fzf reload (used by __file_opener.sh)
format_issues_data() {
    local json_data="$1"
    echo "$json_data" | jq -r '.data.issues.nodes[] |
        (.priority as $p |
            if $p == 1 then "🔴"
            elif $p == 2 then "🟠"
            elif $p == 3 then "🟡"
            elif $p == 4 then "🔵"
            else "⚪"
            end
        ) + " " +
        (.updatedAt | split("T")[0]) + " │ " +
        .team.key + "-" + .identifier + " │ " +
        (.state.name | .[0:12]) + " │ " +
        (if .assignee.name then .assignee.name else "Unassigned" end | .[0:12]) + " │ " +
        (.title | .[0:50]) +
        "\t" + .url'
}

# Execute main only if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        fzf-data)
            validate_env_vars
            issues_json=$(fetch_linear_issues)
            format_issues_data "$issues_json"
            ;;
        *)
            main "$@"
            ;;
    esac
fi