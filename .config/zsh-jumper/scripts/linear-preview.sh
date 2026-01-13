#!/usr/bin/env bash
# Linear issue preview
# Source env vars (LINEAR_API_KEY)
[[ -f ~/.envrc ]] && source ~/.envrc 2>/dev/null

ISSUE=$(echo "$TOKEN" | grep -oE '(DEVOPS|DOC|ENG|IT)-[0-9]+' || true)
[[ -z "$ISSUE" ]] && exit 1
~/dev/dotfiles/scripts/__get_linear_issue.sh "$ISSUE" 2>/dev/null | jq -r '
  .data.issue |
  "# \(.title // "No title")\n\n\(.description // "No description")"
'
