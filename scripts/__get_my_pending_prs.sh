#!/usr/bin/env bash
set -eo pipefail

# Print header
echo "Not a real blocker, just some open PRs pending review"
echo

# Get open PRs using GitHub CLI
gh search prs --author "@me" --owner "loft-sh" --state "open" --json url,title,number 2>/dev/null > /tmp/prs.json

# Process each PR - show as simple list with inline links
jq -r '.[] | "- [ ] " + .title + " [#" + (.number | tostring) + "](" + .url + ")"' /tmp/prs.json 2>/dev/null