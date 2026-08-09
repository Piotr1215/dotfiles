#!/usr/bin/env bash
# Display linear issue, agent task, Claude pane goal, or date/time for tmux status bar
# Two modes: default (fast reader for status bar) and --update (async writer)
set -eo pipefail

# Overridable so the test suite can point the writer at a scratch dir instead of
# clobbering the live status cache of whatever sessions are open.
CACHE_DIR="${TMUX_TASK_CACHE_DIR:-/tmp/tmux_task_status}"
mkdir -p "$CACHE_DIR"

# Fast path: status bar just reads pre-computed file + fresh time
if [ "${1:-}" != "--update" ]; then
    session=$(tmux display-message -p '#S' 2>/dev/null || echo "default")
    # Slashes in session names (e.g. _claude-fix/foo) are illegal in a flat
    # filename, so map them to '-' for the cache key (matches the writer).
    cache_file="$CACHE_DIR/${session//\//-}"
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
    else
        m="work"; [[ -f /tmp/timeoff_mode ]] && m="home"
        echo "$(date +"%a %H:%M") | $m"
    fi
    exit 0
fi

# --- Async update mode (called by tmux hooks in background) ---

truncate_desc() {
    local desc="$1" max="${2:-50}"
    if [ ${#desc} -gt "$max" ]; then
        echo "${desc:0:$((max - 3))}..."
    else
        echo "$desc"
    fi
}

get_pr_desc() {
    command -v gh &> /dev/null || return 0
    local session="$1"
    # PR-based agent sessions are named "<repo>-pr-<num>" (e.g. vcluster-docs-pr-2340).
    # Grab the number after "-pr-"; non-PR sessions bail out so the Linear path below
    # stays untouched. Checked before get_agent_issue because the generic Linear regex
    # would otherwise mis-match "pr-2340" as a bogus issue id "PR-2340".
    local pr_num
    if [[ "$session" =~ -pr-([0-9]+) ]]; then
        pr_num="${BASH_REMATCH[1]}"
    else
        return 0
    fi
    # Resolve owner/repo from the session's active pane (a worktree on the PR branch),
    # then ask gh for the PR title. Sibling of __open_pane_pr.sh (M-p), which opens the
    # same PR in the browser.
    local pane_path url repo title
    pane_path=$(tmux display-message -p -t "$session" '#{pane_current_path}' 2>/dev/null) || return 0
    [ -d "$pane_path" ] || return 0
    url=$(git -C "$pane_path" remote get-url origin 2>/dev/null) || return 0
    [ -n "$url" ] || return 0
    # git@github.com:owner/repo.git or https://github.com/owner/repo.git -> owner/repo
    repo=${url%.git}; repo=${repo#*github.com}; repo=${repo#[:/]}
    title=$(gh pr view "$pr_num" --repo "$repo" --json title --jq '.title' 2>/dev/null) || true
    [ -n "$title" ] && echo "🔀 $(truncate_desc "$title" 60)"
}

get_agent_issue() {
    command -v task &> /dev/null || return 0
    local session="$1"
    local linear_id
    # Match the Linear ID anywhere in the session name, not just at the end.
    # Agent sessions carry a trailing descriptor (e.g. devops-1020-rollout),
    # so an end-anchored ($) match missed them. Mirrors __open_pane_linear.sh (M-a).
    if [[ "$session" =~ ([a-zA-Z]+-[0-9]+) ]]; then
        linear_id=$(echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')
    fi
    [ -z "$linear_id" ] && return 0
    local desc
    desc=$(task rc.verbose=nothing "linear_issue_id:$linear_id" export 2>/dev/null | jq -r '.[0].description // empty' 2>/dev/null) || true
    [ -n "$desc" ] && echo "📋 $desc"
}

get_agent_desc() {
    local session="$1" desc
    # @agent_desc is a session option written by ~/.claude/scripts/__spawn_agent.sh
    # --desc at spawn time. It covers the spawns the two lookups above cannot see:
    # a /ops-spawn-agent worker carries neither a PR number nor a Linear id in its
    # session name, so the status bar had nothing to show but the clock.
    #
    # A session option rather than a file: it is scoped to exactly the session the
    # cache is keyed by, and it dies with the session, so a killed or respawned
    # agent can never leave a stale description behind.
    desc=$(tmux show-options -qv -t "$session" @agent_desc 2>/dev/null) || return 0
    [ -n "$desc" ] || return 0
    # '#' opens a format substitution in a tmux status string, and newlines would
    # split the single-line cache entry. Strip both rather than trust that job
    # output is never re-expanded.
    desc=$(printf '%s' "${desc//\#/}" | tr -d '\n\r\t')
    [ -n "$desc" ] && echo "🤖 $(truncate_desc "$desc" 60)"
}

get_claude_goal() {
    local session="$1" goal
    # @claude_goal is a PANE option written by ~/.claude/scripts/__claude_pane_label.sh
    # from the first sentence of the session's newest away_summary. It covers the
    # home case the three lookups above cannot: an interactive Claude pane carries
    # no PR number, no Linear id, and no spawn-time --desc, so the bar said nothing
    # about the agent sitting in front of you.
    #
    # display-message rather than show-options, and deliberately so: a pane option
    # is invisible to `show-options -t <session>`, but a format resolved against a
    # session renders the ACTIVE pane's value. That is the property that makes this
    # work at all, because it means the bar describes the pane being looked at
    # rather than the session as a whole.
    goal=$(tmux display-message -p -t "$session" '#{@claude_goal}' 2>/dev/null) || return 0
    [ -n "$goal" ] || return 0
    # '#' opens a format substitution in a status string, and newlines would split
    # the single-line cache entry. Same defence as get_agent_desc above.
    goal=$(printf '%s' "${goal//\#/}" | tr -d '\n\r\t')
    # THE CLOCK IS APPENDED AFTER THIS TEXT, and tmux hard-truncates the whole
    # of status-right at status-right-length. So an over-long recap does not
    # merely look untidy: it silently eats the clock off the right-hand end,
    # because the clock is last in the string. That is what a 200-char cap did
    # against a 100-char status-right-length.
    #
    # The budget is derived from the live tmux setting rather than guessed, so
    # changing status-right-length keeps this correct with no second edit.
    # 24 covers " | Sat 00:00 | home" plus the emoji and its space.
    # `if`, NOT `[ ... ] && x`. A trailing && list returns 1 whenever the test is
    # false, and under `set -e` that aborts the update before anything is
    # written, leaving the bar on whatever stale line it already had. That exact
    # shape has broken this file before.
    local limit budget
    limit=$(tmux show-options -gqv status-right-length 2>/dev/null)
    case "$limit" in ''|*[!0-9]*) limit=100 ;; esac
    budget=$(( limit - 24 ))
    if [ "$budget" -lt 20 ]; then budget=20; fi
    # The bar carries a headline, not the recap. It used to spend every
    # character the clock did not need, which put 116 characters of a 280
    # character goal on screen: too long to take in at a glance and still only
    # a fragment. prefix g now shows every source in full on demand, so the
    # always-on line no longer has to try to say everything.
    #
    # 60 is get_agent_desc's cap, so all three text sources read at one width
    # instead of the goal being twice the length of a PR title. The derived
    # budget stays as the ceiling above it: if status-right-length ever drops
    # below 84, the smaller number wins and the clock still survives.
    if [ "$budget" -gt 60 ]; then budget=60; fi
    if [ -n "$goal" ]; then echo "🤖 $(truncate_desc "$goal" "$budget")"; fi
}

update_session() {
    local session="$1"
    local datetime="$(date +"%a %H:%M")"
    local mode="work"
    [[ -f /tmp/timeoff_mode ]] && mode="home"
    datetime="$datetime | $mode"
    local prefix=""

    # Order is precedence. PR and Linear are live lookups that resolve richer text
    # than a spawn-time label, and both already work, so the explicit description
    # slots in behind them: adding it can only fill a gap, never displace a line
    # that renders today.
    # `|| true` on every one of these, because each getter ends in
    # `[ -n "$x" ] && echo ...` and so returns 1 when it finds nothing. Under
    # `set -e` that failure propagates out of the assignment and kills the whole
    # update: a session named like a Linear issue with no matching task (say
    # worker-2-cleanup) aborted here and never got a cache entry written at all,
    # so its status bar kept whatever stale line it already had. Finding nothing
    # is the normal case for this chain, not an error.
    prefix=$(get_pr_desc "$session") || true
    if [ -z "$prefix" ]; then
        prefix=$(get_agent_issue "$session") || true
    fi
    if [ -z "$prefix" ]; then
        prefix=$(get_agent_desc "$session") || true
    fi
    # Last link, behind every explicit label: an interactive Claude pane has no
    # PR, no Linear id and no spawn --desc, so without this the bar fell through to
    # the bare clock and said nothing about the agent in front of you. The mpv
    # track used to sit at the end of this chain and was removed: this bar is for
    # what the agent is doing, and the music was crowding it out.
    if [ -z "$prefix" ]; then
        prefix=$(get_claude_goal "$session") || true
    fi

    local cache_key="${session//\//-}"
    if [ -n "$prefix" ]; then
        echo "$prefix | $datetime" > "$CACHE_DIR/${cache_key}"
    else
        echo "$datetime" > "$CACHE_DIR/${cache_key}"
    fi
}

# Prevent pile-up: skip if another update is already running
LOCK_FILE="/tmp/tmux_task_update.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

# Update only the current session (or all with --update-all)
if [ "${2:-}" = "all" ]; then
    while IFS= read -r session; do
        update_session "$session"
    done < <(tmux list-sessions -F '#S' 2>/dev/null)
else
    current=$(tmux display-message -p '#S' 2>/dev/null || exit 0)
    update_session "$current"
fi
