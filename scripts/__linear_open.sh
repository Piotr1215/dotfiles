#!/usr/bin/env bash
# __linear_open.sh
# Open a Linear issue id (TEAM-NUMBER) or a GitHub PR reference in the browser
# from the Alacritty ctrl+4 hint. Alacritty appends the matched text as the last
# argument. This script is the single ctrl+4 dispatcher: it inspects the matched
# text and routes it.
#
# Routing rule (first match wins):
#   1. A full GitHub PR URL, https://github.com/<org>/<repo>/pull/<n>, opens as-is.
#   2. A short PR ref, <owner>/<repo>#<n>, becomes
#      https://github.com/<owner>/<repo>/pull/<n>. A bare #<n> is NOT handled
#      (no repo context, too ambiguous).
#   3. Otherwise a Linear issue id (TEAM-NUMBER) opens
#      https://linear.app/loft/issue/<ID>. The team prefix is validated against
#      the live Linear team-key list, pulled once via the API and cached, so a
#      stray match (UTF-8, SHA-256, ISO-8601) does not open a bogus page. If the
#      key list cannot be fetched and nothing is cached, the id is opened anyway:
#      the user triggered the hint deliberately.
#
# Usage:
#   __linear_open.sh DEVOPS-1027
#   __linear_open.sh loft-sh/vcluster#8234
#   __linear_open.sh https://github.com/loft-sh/vcluster/pull/8234
#   LINEAR_OPEN_DRYRUN=1 __linear_open.sh DEVOPS-1027   # print, do not open
set -eo pipefail

# Alacritty spawns hint commands without the interactive shell env, so pull
# LINEAR_API_KEY (and PATH bits) the same way the cron scripts do.
# shellcheck disable=SC1091
[[ -f "$HOME/.envrc" ]] && source "$HOME/.envrc"

WORKSPACE="loft"
CACHE_DIR="$HOME/.cache/linear"
CACHE_FILE="$CACHE_DIR/team-keys"
TTL=86400 # refresh the key list at most once a day

raw="${1:-}"
[[ -z "$raw" ]] && exit 0

# open_browser: emit OPEN in dry-run, otherwise hand the url to the browser the
# same way the Linear path always has.
open_browser() {
    local url="$1"
    if [[ -n "${LINEAR_OPEN_DRYRUN:-}" ]]; then
        echo "OPEN $url"
        return
    fi
    setsid xdg-open "$url" >/dev/null 2>&1 &
}

# --- GitHub PR routing -----------------------------------------------------
# A full PR URL opens verbatim. The `|| true` keeps a no-match grep (exit 1)
# from tripping `set -e`/`pipefail` so routing can fall through.
pr_url=$(grep -oE 'https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+' <<<"$raw" | head -1 || true)
if [[ -n "$pr_url" ]]; then
    open_browser "$pr_url"
    exit 0
fi

# A short ref <owner>/<repo>#<n> expands to the canonical pull URL.
pr_ref=$(grep -oE '[A-Za-z0-9._-]+/[A-Za-z0-9._-]+#[0-9]+' <<<"$raw" | head -1 || true)
if [[ -n "$pr_ref" ]]; then
    owner_repo="${pr_ref%#*}"
    number="${pr_ref##*#}"
    open_browser "https://github.com/$owner_repo/pull/$number"
    exit 0
fi

# --- Linear routing --------------------------------------------------------
# Extract a TEAM-NUMBER token from whatever was matched, normalize to uppercase.
match=$(grep -oE '[A-Za-z][A-Za-z0-9]*-[0-9]+' <<<"$raw" | head -1 || true)
[[ -z "$match" ]] && exit 0
id=$(tr '[:lower:]' '[:upper:]' <<<"$match")
team="${id%-*}"

# Pull all team keys from Linear (uppercased), one per line, on stdout.
fetch_keys() {
    [[ -z "${LINEAR_API_KEY:-}" ]] && return 1
    local resp
    resp=$(curl -s --max-time 5 -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: $LINEAR_API_KEY" \
        --data '{"query":"{ teams(first: 250) { nodes { key } } }"}' \
        https://api.linear.app/graphql) || return 1
    printf '%s' "$resp" | jq -e -r '.data.teams.nodes[].key' 2>/dev/null
}

# Refresh the cache when missing or older than TTL.
refresh=1
if [[ -f "$CACHE_FILE" ]]; then
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
    [[ "$age" -lt "$TTL" ]] && refresh=0
fi
if [[ "$refresh" -eq 1 ]]; then
    mkdir -p "$CACHE_DIR"
    if keys=$(fetch_keys) && [[ -n "$keys" ]]; then
        printf '%s\n' "$keys" | tr '[:lower:]' '[:upper:]' | sort -u >"$CACHE_FILE"
    fi
fi

open_url() {
    open_browser "https://linear.app/$WORKSPACE/issue/$id"
}

if [[ -s "$CACHE_FILE" ]]; then
    if grep -qx "$team" "$CACHE_FILE"; then
        open_url
    elif [[ -n "${LINEAR_OPEN_DRYRUN:-}" ]]; then
        echo "SKIP unknown team '$team' in $id"
    elif command -v notify-send >/dev/null 2>&1; then
        notify-send "Linear" "Unknown team '$team' in $id, not opening" || true
    fi
else
    # No key list available; honor the deliberate trigger.
    open_url
fi
