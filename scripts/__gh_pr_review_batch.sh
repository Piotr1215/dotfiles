#!/usr/bin/env bash
# PR review script
# Usage: __gh_pr_review_batch.sh <json_file> [--dry-run]
set -eo pipefail

# Error codes for 
E_NO_FILE=1
E_INVALID_JSON=2
E_NO_PR=3
E_NO_REPO=4
E_GH_AUTH=5
E_API_FAIL=6
E_INVALID_TYPE=7

# Structured error output
error_exit() {
    local code=$1
    local msg=$2
    echo "ERROR:$code:$msg" >&2
    exit $code
}

# Input validation
JSON_FILE="${1}"
DRY_RUN="${2:-}"

[[ -z "$JSON_FILE" ]] && error_exit $E_NO_FILE "No JSON file provided"
[[ ! -f "$JSON_FILE" ]] && error_exit $E_NO_FILE "File not found: $JSON_FILE"

# Validate JSON structure
if ! jq empty "$JSON_FILE" 2>/dev/null; then
    error_exit $E_INVALID_JSON "Invalid JSON in $JSON_FILE"
fi

# Extract and validate required fields
PR_NUMBER=$(jq -r '.pr_number // empty' "$JSON_FILE" 2>/dev/null)
[[ -z "$PR_NUMBER" ]] && error_exit $E_NO_PR "Missing pr_number in JSON"
[[ ! "$PR_NUMBER" =~ ^[0-9]+$ ]] && error_exit $E_NO_PR "Invalid PR number: $PR_NUMBER"

REVIEW_BODY=$(jq -r '.review_body // ""' "$JSON_FILE" 2>/dev/null)
REVIEW_TYPE=$(jq -r '.review_type // "COMMENT"' "$JSON_FILE" 2>/dev/null)

# Validate review type
case "$REVIEW_TYPE" in
    COMMENT|APPROVE|REQUEST_CHANGES) ;;
    *) error_exit $E_INVALID_TYPE "Invalid review type: $REVIEW_TYPE. Must be COMMENT, APPROVE, or REQUEST_CHANGES" ;;
esac

# Check gh CLI authentication
if ! gh auth status >/dev/null 2>&1; then
    error_exit $E_GH_AUTH "GitHub CLI not authenticated. Run: gh auth login"
fi

# Determine repository (multiple fallback methods)
REPO=""
# Method 1: From JSON file
REPO=$(jq -r '.repository // empty' "$JSON_FILE" 2>/dev/null || echo "")
# Method 2: Current directory
if [[ -z "$REPO" ]]; then
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
fi
# Method 3: Git remote
if [[ -z "$REPO" ]] && command -v git >/dev/null 2>&1; then
    REPO=$(git remote get-url origin 2>/dev/null | sed -E 's/.*[:/]([^/]+\/[^/]+)(\.git)?$/\1/' || echo "")
fi
[[ -z "$REPO" ]] && error_exit $E_NO_REPO "Cannot determine repository"

# Verify PR exists
if ! gh pr view "$PR_NUMBER" --repo "$REPO" --json number >/dev/null 2>&1; then
    error_exit $E_NO_PR "PR #$PR_NUMBER not found in $REPO"
fi

# Build review JSON for GitHub API
build_review_json() {
    local comments_array="[]"
    
    # Process comments if they exist
    if jq -e '.comments | type == "array" and length > 0' "$JSON_FILE" >/dev/null 2>&1; then
        comments_array=$(jq '[
            .comments[] |
            select(.file != null and .line != null and (.comment != null or .suggestion != null)) |
            {
                path: .file,
                line: (.line | tonumber),
                body: (
                    if .suggestion and (.suggestion | type == "string") and (.suggestion | length > 0) then
                        if .comment then
                            (.comment + "\n```suggestion\n" + .suggestion + "\n```")
                        else
                            ("```suggestion\n" + .suggestion + "\n```")
                        end
                    else
                        .comment
                    end
                )
            }
        ]' "$JSON_FILE" 2>/dev/null || echo "[]")
    fi
    
    # Create final review object
    jq -n \
        --arg body "$REVIEW_BODY" \
        --arg event "$REVIEW_TYPE" \
        --argjson comments "$comments_array" \
        '{body: $body, event: $event, comments: $comments}'
}

# Build the review JSON
REVIEW_JSON=$(build_review_json)

# Validate the generated JSON
if ! echo "$REVIEW_JSON" | jq empty 2>/dev/null; then
    error_exit $E_INVALID_JSON "Failed to generate valid review JSON"
fi

# Dry run mode - output JSON and exit
if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "DRY_RUN:"
    echo "$REVIEW_JSON" | jq -c '.'
    exit 0
fi

# Submit review to GitHub with retries
submit_review() {
    local attempt=1
    local max_attempts=3
    local temp_response=$(mktemp)
    local temp_error=$(mktemp)
    trap "rm -f $temp_response $temp_error" RETURN
    
    while [[ $attempt -le $max_attempts ]]; do
        if gh api \
            --method POST \
            "/repos/${REPO}/pulls/${PR_NUMBER}/reviews" \
            --input - <<< "$REVIEW_JSON" \
            > "$temp_response" 2> "$temp_error"; then
            
            # Validate response is valid JSON
            if jq empty "$temp_response" 2>/dev/null; then
                cat "$temp_response"
                return 0
            fi
        fi
        
        # Log attempt failure for debugging 
        echo "RETRY:$attempt/$max_attempts" >&2
        ((attempt++))
        [[ $attempt -le $max_attempts ]] && sleep 2
    done
    
    # All attempts failed
    local error_msg=$(cat "$temp_error" 2>/dev/null || echo "Unknown error")
    error_exit $E_API_FAIL "API call failed: $error_msg"
}

# Submit the review
RESPONSE=$(submit_review)

# Parse response
REVIEW_ID=$(echo "$RESPONSE" | jq -r '.id // empty' 2>/dev/null)
REVIEW_URL=$(echo "$RESPONSE" | jq -r '.html_url // empty' 2>/dev/null)
REVIEW_STATE=$(echo "$RESPONSE" | jq -r '.state // empty' 2>/dev/null)
COMMENT_COUNT=$(jq '.comments | length' "$JSON_FILE" 2>/dev/null || echo "0")

[[ -z "$REVIEW_ID" ]] && error_exit $E_API_FAIL "No review ID in response"

# Output success in structured format 
echo "SUCCESS"
echo "ID:$REVIEW_ID"
echo "URL:$REVIEW_URL"
echo "STATE:$REVIEW_STATE"
echo "COMMENTS:$COMMENT_COUNT"
echo "PR:$PR_NUMBER"
echo "REPO:$REPO"

# Clean up input file
rm -f "$JSON_FILE" 2>/dev/null || true
