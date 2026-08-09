#!/usr/bin/env bash
# Display PR title, Linear issue, pane goal, or date/time for tmux status bar
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

get_claude_goal() {
    local session="$1" goal
    # @claude_goal is a PANE option written by ~/.claude/scripts/__claude_pane_label.sh
    # from the first sentence of the session's newest away_summary. It covers the
    # fallback case the two live lookups above cannot: an ordinary interactive or
    # spawned pane carries no PR number or Linear id in its session name.
    #
    # display-message rather than show-options, and deliberately so: a pane option
    # is invisible to `show-options -t <session>`, but a format resolved against a
    # session renders the ACTIVE pane's value. That is the property that makes this
    # work at all, because it means the bar describes the pane being looked at
    # rather than the session as a whole.
    goal=$(tmux display-message -p -t "$session" '#{@claude_goal}' 2>/dev/null) || return 0
    [ -n "$goal" ] || return 0
    # '#' opens a format substitution in a status string, and newlines would split
    # the single-line cache entry.
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
    # 60 matches the PR title cap. The derived budget stays as the ceiling above
    # it: if status-right-length ever drops below 84, the smaller number wins and
    # the clock still survives.
    if [ "$budget" -gt 60 ]; then budget=60; fi
    if [ -n "$goal" ]; then echo "🤖 $(truncate_desc "$goal" "$budget")"; fi
}

update_session() {
    local session="$1"
    local datetime
    datetime=$(date +"%a %H:%M")
    local mode="work"
    [[ -f /tmp/timeoff_mode ]] && mode="home"
    datetime="$datetime | $mode"
    local prefix=""

    # Order is precedence. PR and Linear are live lookups that resolve richer text
    # than the pane goal. The goal remains independently available to prefix g.
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
    # Last link, behind the two explicit labels: ordinary panes have no PR or
    # Linear id, so without this the bar falls through to the bare clock and says
    # nothing about the agent in front of you. The mpv
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

# Prevent pile-up without dropping the newest goal. The hook path must return
# at once, so a busy first writer launches one detached retry. That retry waits
# for the current writer and then rebuilds from the latest pane options.
LOCK_FILE="${TMUX_TASK_LOCK_FILE:-/tmp/tmux_task_update.lock}"
exec 9>"$LOCK_FILE"
if [ "${TMUX_TASK_LOCK_RETRY:-0}" = "1" ]; then
    flock -w "${TMUX_TASK_LOCK_RETRY_WAIT:-5}" 9 || exit 0
elif ! flock -n 9; then
    setsid env TMUX_TASK_LOCK_RETRY=1 "$0" "$@" </dev/null >/dev/null 2>&1 &
    exit 0
fi

# Update only the current session (or all with --update-all)
if [ "${2:-}" = "all" ]; then
    while IFS= read -r session; do
        update_session "$session"
    done < <(tmux list-sessions -F '#S' 2>/dev/null)
else
    current=$(tmux display-message -p '#S' 2>/dev/null || exit 0)
    update_session "$current"
fi
