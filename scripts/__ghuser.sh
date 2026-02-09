#!/usr/bin/env bash
# Search GitHub users by name or handle
# Usage: ghuser pascal  OR  ghuser (fzf picker)
# Cache: 1 hour in /tmp, refresh with: ghuser --refresh

set -eo pipefail

cache_file="/tmp/loft-gh-users.txt"
cache_ttl=18000  # 5 hours

refresh_cache() {
  echo "Refreshing cache..." >&2

  # Get all logins into array
  mapfile -t logins < <(gh api /orgs/loft-sh/members --paginate --jq '.[].login')

  # Build GraphQL query for batch user lookup
  query="query {"
  for i in "${!logins[@]}"; do
    query+=" u$i: user(login: \"${logins[$i]}\") { login name }"
  done
  query+=" }"

  gh api graphql -f query="$query" --jq '.data | to_entries[] | "\(.value.login)|\(.value.name // "")"' > "$cache_file"
  echo "Done (${#logins[@]} users)." >&2
}

# Force refresh
[[ "$1" == "--refresh" ]] && { refresh_cache; exit 0; }

# Auto-refresh if stale (background) or missing (foreground)
if [[ ! -f "$cache_file" ]]; then
  refresh_cache
elif [[ $(( $(date +%s) - $(stat -c %Y "$cache_file") )) -gt $cache_ttl ]]; then
  refresh_cache &
fi

if [[ -z "$1" ]]; then
  cat "$cache_file" | fzf -d'|' --with-nth=2,1 --preview 'echo "GitHub: {1}"' | cut -d'|' -f1
else
  grep -i "$*" "$cache_file" | cut -d'|' -f1
fi
