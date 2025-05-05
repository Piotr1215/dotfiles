#!/usr/bin/env bash

# __get_linear_issue.sh
# Gets detailed information about a Linear issue by ID, including all comments
# 
# Usage: ./__get_linear_issue.sh <issue-id>
# Example: ./__get_linear_issue.sh eng-6666
#
# Notes:
#   - Requires LINEAR_API_KEY environment variable to be set
#   - Issue ID is case-insensitive (eng-6666 and ENG-6666 are equivalent)
#   - Returns a JSON object with all issue details and comments

set -eo pipefail
IFS=$'\n\t'

# Logger with timestamp
log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

# Validate necessary environment variables
validate_env_vars() {
    local required_vars=(LINEAR_API_KEY)
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "Error: Environment variable $var is not set." >&2
            exit 1
        fi
    done
}

# Get detailed information for a Linear issue by ID
get_linear_issue() {
    local issue_id="$1"
    
    if [[ -z "$issue_id" ]]; then
        echo "Error: Issue ID is required." >&2
        exit 1
    fi
    
    # Handle different issue ID formats
    # If only the numeric ID was provided, exit with error
    if [[ "$issue_id" =~ ^[0-9]+$ ]]; then
        echo "Error: Please provide a full issue ID with team prefix (e.g., ENG-123, DOC-456)" >&2
        exit 1
    fi
    
    # Convert ID to uppercase
    issue_id=$(echo "$issue_id" | tr '[:lower:]' '[:upper:]')
    
    # Make API call to get the specific issue with all details
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: $LINEAR_API_KEY" \
        --data '{"query": "query IssueWithComments($id: String!) { issue(id: $id) { id identifier title description url state { id name color } project { id name } team { id name key } assignee { id name email } labels { nodes { id name color } } priority createdAt updatedAt completedAt comments { nodes { id body user { id name } createdAt updatedAt } } } }", "variables": {"id": "'"$issue_id"'"}}' \
        https://api.linear.app/graphql | jq '.'
}

# Main function
main() {
    validate_env_vars
    
    # Check if issue ID was provided
    if [[ $# -eq 0 ]]; then
        echo "Error: Please provide a Linear issue ID (e.g., ENG-123, DOC-456)" >&2
        exit 1
    fi
    
    local issue_id="$1"
    get_linear_issue "$issue_id"
}

# Execute main only if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
