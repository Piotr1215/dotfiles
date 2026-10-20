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

  # SSO email per login, the fallback for members whose GitHub profile has no name.
  # Needs org admin; without it every member keeps only the profile name.
  # shellcheck disable=SC2016  # $endCursor is a GraphQL variable, not shell
  local sso_query='query($endCursor: String) { organization(login: "loft-sh") { samlIdentityProvider {
    externalIdentities(first: 100, after: $endCursor) { pageInfo { hasNextPage endCursor }
      nodes { user { login } samlIdentity { nameId } } } } } }'
  local sso
  sso=$(gh api graphql --paginate -f query="$sso_query" \
    --jq '.data.organization.samlIdentityProvider.externalIdentities.nodes[] | select(.user) | "\(.user.login)|\(.samlIdentity.nameId // "")"' 2>/dev/null || true)

  gh api graphql -f query="$query" --jq '.data | to_entries[] | "\(.value.login)|\(.value.name // "")"' |
    awk -F'|' -v sso="$sso" 'BEGIN { n = split(sso, rows, "\n"); for (i = 1; i <= n; i++) { split(rows[i], f, "|"); email[f[1]] = f[2] } }
      { name = $2; if (name == "" && ($1 in email)) name = email[$1]; print $1 "|" name }' > "$cache_file"
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

# Dump the raw cache (login|name), for reuse by other tools (e.g. value-picker).
[[ "$1" == "--list" ]] && { cat "$cache_file"; exit 0; }

if [[ -z "$1" ]]; then
  cat "$cache_file" | fzf -d'|' --with-nth=2,1 --preview 'echo "GitHub: {1}"' | cut -d'|' -f1
else
  grep -i "$*" "$cache_file" | cut -d'|' -f1
fi
