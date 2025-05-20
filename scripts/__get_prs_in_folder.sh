#!/usr/bin/env bash

set -e

# Default settings
DAYS_AGO=30
MAX_PRS=50

# Check required commands
if ! command -v fd &> /dev/null; then
  echo "Error: 'fd' is not installed. Please install it first."
  exit 1
fi

if ! command -v gh &> /dev/null; then
  echo "Error: GitHub CLI (gh) is not installed. Please install it first."
  exit 1
fi

if ! command -v fzf &> /dev/null; then
  echo "Error: fzf is not installed. Please install it first."
  exit 1
fi

if [ $# -eq 0 ]; then
  echo "Select a folder (including hidden ones like .github):"
  FOLDER_PATH=$(fd --type d --hidden --exclude .git | fzf --height 40% --preview 'ls -la {}')
  if [ -z "$FOLDER_PATH" ]; then
    echo "No folder selected. Exiting."
    exit 0
  fi
else
  FOLDER_PATH="$1"
fi

if [ ! -d "$FOLDER_PATH" ]; then
  echo "Error: '$FOLDER_PATH' is not a valid directory"
  exit 1
fi

FOLDER_PATH="${FOLDER_PATH#./}"

# Get repo info
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
if [ -z "$REPO" ]; then
  echo "Error: Not in a GitHub repository or unable to determine repository."
  exit 1
fi

SINCE_DATE=$(date -d "$DAYS_AGO days ago" +%Y-%m-%d)

echo "🔍 Searching for PRs modifying files in: $FOLDER_PATH"
echo "📅 Time range: Last $DAYS_AGO days"
echo "🔄 Repository: $REPO"

echo "Fetching recent PRs..."
RECENT_PRS=$(gh pr list --repo "$REPO" --state merged --limit $MAX_PRS --search "merged:>$SINCE_DATE" --json number,title,mergedAt,author,url,files --jq '.')

if [ -z "$RECENT_PRS" ] || [ "$RECENT_PRS" == "[]" ]; then
  echo "No PRs found in the last $DAYS_AGO days."
  exit 0
fi

echo "Filtering PRs that modified files in $FOLDER_PATH..."
MATCHING_PRS=$(echo "$RECENT_PRS" | jq --arg path "$FOLDER_PATH/" \
  '[.[] | select(.files[].path | startswith($path)) | {number: .number, title: .title, mergedAt: .mergedAt, author: .author.login, url: .url}]')

PR_COUNT=$(echo "$MATCHING_PRS" | jq 'length')
if [ "$PR_COUNT" -eq 0 ]; then
  echo "No PRs found modifying files in '$FOLDER_PATH' in the last $DAYS_AGO days."
  exit 0
fi

echo "Found $PR_COUNT PRs that modified files in $FOLDER_PATH"

FORMATTED_PRS=$(echo "$MATCHING_PRS" | jq -r '.[] | [.number, .title, .author, .mergedAt] | @tsv' | \
  awk -F'\t' '{printf "%-5s | %-60.60s | %-15.15s | %s\n", $1, $2, $3, $4}')

SELECTED=$(echo "$FORMATTED_PRS" | fzf --height 40% \
  --header="PRs modifying files in $FOLDER_PATH (use up/down arrows, press Enter to select)" \
  --preview "echo {} | awk '{print \$1}' | xargs gh pr view --repo $REPO")

if [ -n "$SELECTED" ]; then
  PR_NUMBER=$(echo "$SELECTED" | awk '{print $1}')
  echo "Opening PR #$PR_NUMBER in browser..."
  gh pr view --web "$PR_NUMBER" --repo "$REPO"
fi
