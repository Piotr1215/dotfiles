#!/usr/bin/env bash
# PROJECT: slack-thread-annotations
# See: __github_issue_sync.sh (writes the "slack: <url>" annotations), .taskopenrc
#
# Opens a Slack message permalink in the Slack desktop app instead of a browser
# tab. Called by the `slack` action in .taskopenrc, which hands it the url part
# of a "slack: <url>" annotation.
#
# Slack's own documentation (docs.slack.dev/interactivity/deep-linking) covers
# exactly one channel form, `slack://channel?team=<TEAM_ID>&id=<CHANNEL_ID>`,
# with team required, and documents NO parameter for addressing a single
# message. The `message` and `thread_ts` parameters added below are undocumented
# but are what the desktop client honours; if a Slack release ever stops
# honouring them the link still resolves to the right channel, which is why they
# are worth using and why nothing here depends on them.
#
# The team id is the one value a permalink cannot supply: it carries the
# workspace DOMAIN (loft-labs-inc) and Slack's scheme wants the id (T0243...).
# Rather than guess it, resolve it explicitly and fall back to the browser with
# a remedy when it is unknown.

set -eo pipefail

TEAMS_CONFIG="${SLACK_OPEN_TEAMS_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/slack-open/teams}"
SLACK_STATE_DIR="${SLACK_STATE_DIR:-$HOME/.var/app/com.slack.Slack/config/Slack}"
OPENER="${SLACK_OPEN_OPENER:-xdg-open}"

usage() {
    cat <<'EOF'
Usage: __slack_open.sh <slack-permalink>
       __slack_open.sh --detect

Opens a Slack message permalink in the Slack desktop app.

  <slack-permalink>  https://<workspace>.slack.com/archives/<CHANNEL>/p<TS>[?thread_ts=..]
  --detect           List team ids found in the local Slack app state, to fill
                     in the workspace -> team id map.

Team id resolution order:
  1. $SLACK_TEAM_ID
  2. <workspace> <TEAM_ID> line in the teams config
  3. none found: opens the original https link in the browser instead

Teams config: $XDG_CONFIG_HOME/slack-open/teams (default ~/.config/slack-open/teams)
  # one "workspace teamid" pair per line, # comments allowed
  loft-labs-inc T0123456789
EOF
}

# Team ids the installed Slack app has on disk, most frequently referenced
# first. Slack stores no clean domain -> id mapping we can read, so this is a
# discovery aid for a human filling in the config once, never an auto-answer:
# picking the most common id for the user would be a guess wearing a fact's
# clothes.
detect_team_ids() {
    if [[ ! -d "$SLACK_STATE_DIR" ]]; then
        echo "No local Slack app state at $SLACK_STATE_DIR" >&2
        return 1
    fi

    echo "Team ids referenced in $SLACK_STATE_DIR (most referenced first):"
    # \b and the digit filter matter: a bare T[0-9A-Z]{8,12} also matches the
    # tail of ordinary upper-case words in the app bundle (NOTIFICATIONS,
    # INTEGRATIONS, TABCOMPLETE), which buries the real id in noise. Every Slack
    # team id contains at least one digit.
    { grep -rhoaE '\bT[A-Z0-9]{7,11}\b' "$SLACK_STATE_DIR" 2>/dev/null || true; } \
        | grep -E '[0-9]' \
        | sort | uniq -c | sort -rn | head -5 \
        | while read -r count team_id; do
            printf '  %-14s (%s references)\n' "$team_id" "$count"
        done

    echo
    echo "Take the workspace from your own permalink: the <workspace> in"
    echo "https://<workspace>.slack.com/archives/... . Then record the pair in"
    echo "$TEAMS_CONFIG, e.g.:"
    echo "  loft-labs-inc T0123456789"
}

# Look a workspace domain up in the teams config. Silent on a miss; the caller
# decides what a miss means.
team_id_for_workspace() {
    local workspace="$1"
    local cfg_workspace cfg_team

    [[ -r "$TEAMS_CONFIG" ]] || return 1

    while read -r cfg_workspace cfg_team _; do
        [[ -z "$cfg_workspace" || "$cfg_workspace" == \#* ]] && continue
        if [[ "$cfg_workspace" == "$workspace" ]]; then
            echo "$cfg_team"
            return 0
        fi
    done < "$TEAMS_CONFIG"

    return 1
}

# Slack permalinks encode the message timestamp as p<seconds><microseconds>
# with the dot removed: p1785876243182299 is 1785876243.182299. The last six
# digits are always the microseconds, so split from the right.
permalink_ts_to_message_ts() {
    local raw="$1"
    [[ "$raw" =~ ^[0-9]{7,}$ ]] || return 1
    echo "${raw:0:${#raw}-6}.${raw: -6}"
}

main() {
    local url="${1:-}"

    case "$url" in
        -h|--help) usage; exit 0 ;;
        "")        usage >&2; exit 1 ;;
        --detect)  if detect_team_ids; then exit 0; else exit 1; fi ;;
    esac

    # Parse https://<workspace>.slack.com/archives/<CHANNEL>/p<DIGITS>[?query]
    local workspace channel raw_ts query
    if [[ ! "$url" =~ ^https?://([A-Za-z0-9._-]+)\.slack\.com/archives/([A-Za-z0-9]+)/p([0-9]+)(\?(.*))?$ ]]; then
        # Not a message permalink (a channel link, a Slack file, a canvas).
        # Nothing to convert, so hand it to the browser rather than fail: the
        # user asked to open a link, not to be told about a regex.
        echo "Not a Slack message permalink, opening in browser: $url" >&2
        exec "$OPENER" "$url"
    fi
    workspace="${BASH_REMATCH[1]}"
    channel="${BASH_REMATCH[2]}"
    raw_ts="${BASH_REMATCH[3]}"
    query="${BASH_REMATCH[5]}"

    local message_ts
    if ! message_ts=$(permalink_ts_to_message_ts "$raw_ts"); then
        echo "Unparseable message timestamp 'p$raw_ts', opening in browser: $url" >&2
        exec "$OPENER" "$url"
    fi

    # A reply carries thread_ts; opening it addresses the thread rather than
    # just the parent channel.
    local thread_ts=""
    if [[ "$query" =~ (^|&)thread_ts=([0-9.]+) ]]; then
        thread_ts="${BASH_REMATCH[2]}"
    fi

    local team_id="${SLACK_TEAM_ID:-}"
    if [[ -z "$team_id" ]]; then
        team_id=$(team_id_for_workspace "$workspace" || true)
    fi

    if [[ -z "$team_id" ]]; then
        echo "No team id for workspace '$workspace', opening in browser instead." >&2
        echo "To open in the Slack app: run '$(basename "$0") --detect', then add a line" >&2
        echo "'$workspace <TEAM_ID>' to $TEAMS_CONFIG (or set SLACK_TEAM_ID)." >&2
        exec "$OPENER" "$url"
    fi

    local deep_link="slack://channel?team=${team_id}&id=${channel}&message=${message_ts}"
    [[ -n "$thread_ts" ]] && deep_link+="&thread_ts=${thread_ts}"

    exec "$OPENER" "$deep_link"
}

main "$@"
