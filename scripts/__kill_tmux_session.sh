#!/usr/bin/env bash
set -eo pipefail

# True when `tmuxinator stop <session>` would stop this very session. A
# project file sharing the session's name is not enough: stop targets the
# project's `name:` field, which can differ from the filename. dev.yml once
# said `name: loft`, so M-e on "dev" did nothing, or closed "loft" if running.
is_tmuxinator_session() {
    local session="$1" rendered
    command -v tmuxinator >/dev/null 2>&1 || return 1
    tmuxinator list 2>/dev/null | tr -s ' ' '\n' | grep -qx "$session" || return 1
    rendered=$(tmuxinator debug "$session" 2>/dev/null) || return 1
    grep -qF "new-session -d -s $(printf '%q' "$session") " <<<"$rendered"
}

# Skip the picker when sourced (e.g. by tests) so functions can be exercised
# without touching live sessions.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] || return 0

# Get current session name
current_session=$(tmux display-message -p '#S' 2>/dev/null || echo "")

# List all sessions with current session first
{
    # Show current session first if we're in tmux
    if [ -n "$current_session" ]; then
        echo "$current_session"
    fi
    
    # Show all other sessions
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v "^${current_session}$" || true
} | fzf --reverse --header="Kill Session (Current: ${current_session:-none})" | while read -r session_to_kill; do
    if [ -n "$session_to_kill" ]; then
        # If killing current session, switch to previous session first
        if [ "$session_to_kill" = "$current_session" ]; then
            tmux switch-client -l 2>/dev/null || tmux switch-client -n 2>/dev/null || true
        fi
        # Prefer `tmuxinator stop` when the session matches a tmuxinator
        # project — it runs on_project_stop hooks (cleanup of background
        # processes, FIFOs, lockfiles) before killing the session. Falls
        # back to raw kill-session for ad-hoc sessions.
        if is_tmuxinator_session "$session_to_kill"; then
            tmuxinator stop "$session_to_kill"
        else
            tmux kill-session -t "$session_to_kill"
        fi
    fi
done