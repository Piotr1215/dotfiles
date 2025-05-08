#!/usr/bin/env bash
set -eo pipefail

# Print header
echo "Not a real blocker, just some open PRs pending review"
echo

# Get open PRs using GitHub CLI
gh search prs --author "@me" --owner "loft-sh" --state "open" --json url,title > /tmp/prs.json

# Process each PR with the exact format needed
jq -r '.[] | .title + "|" + .url' /tmp/prs.json | while IFS='|' read -r title url; do
  # Format exactly as requested
  echo "- [ ] $title [[1]]($url)"
done