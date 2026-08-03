#!/usr/bin/env bash
# Tell a Claude session running in a tmux pane that the pane's kubernetes
# connection just changed.
#
# kctx pins each pane's KUBECONFIG to a stable runtime path and rewrites the
# selection in place, so a swap reaches any process that already holds that
# path. Claude has no way to notice: nothing re-reads the environment
# mid-session, the pane border is not in its context, and the shell hook that
# would reassert the pair cannot run while claude holds the pane.
#
# What this script must not do is assert that the swap is live for the agent.
# Every Bash tool call is a fresh shell, and its KUBECONFIG comes from the
# claude process environment, which the profile and direnv can have set to
# something else entirely. A worktree .envrc that exports KUBECONFIG wins over
# the pane pair for the whole session, and the swap never reaches a single tool
# call. An agent told "your KUBECONFIG already points at it" then reads the
# wrong cluster with full confidence. So the message reports the change, names
# the pane kubeconfig, and asks for one verification command.
#
# Usage: __kctx_claude_notify.sh <pane-id>
#
# No-ops when the pane holds no claude process, so it is safe to call from the
# picker for every swap.

set -eo pipefail

# The popup that calls this is still on screen; let it close before typing.
readonly SETTLE_DELAY="${KCTX_NOTIFY_SETTLE_DELAY:-0.3}"
# Claude's TUI needs the line buffered before the submit key arrives.
readonly ENTER_DELAY="${KCTX_NOTIFY_ENTER_DELAY:-0.3}"
readonly KCTX_BIN="${KCTX_BIN:-kctx}"
# Overridable so the tests can supply a process environment fixture.
readonly PROC_DIR="${KCTX_NOTIFY_PROC_DIR:-/proc}"

usage() {
    echo "Usage: $(basename "$0") <pane-id>" >&2
    echo "  pane-id: tmux pane id, e.g. %33" >&2
}

# Print the pid of a claude process living under the pane's process tree.
# claude is rarely the pane process itself: the pane holds a shell, and claude
# sits below it, sometimes under the __claude_with_monitor.sh wrapper. One ps
# snapshot walked upwards beats recursing with a process call per level.
pane_claude_pid() {
    local pane="$1"
    local pane_pid

    pane_pid="$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null)" || return 1
    [[ "$pane_pid" =~ ^[0-9]+$ ]] || return 1

    ps -eo pid=,ppid=,comm= | awk -v root="$pane_pid" '
        { ppid[$1] = $2; comm[$1] = $3 }
        END {
            for (pid in comm) {
                if (comm[pid] != "claude") continue
                p = pid
                hops = 0
                while (p != "" && p != "0" && hops++ < 32) {
                    if (p == root) { print pid; exit 0 }
                    p = ppid[p]
                }
            }
            exit 1
        }'
}

# kctx writes both options itself, so they are current even when the pane's
# shell is blocked by claude. @kctx_display is the friendly alias and is empty
# for connections that have none.
current_connection() {
    local pane="$1"
    local display

    display="$(tmux show-options -pqv -t "$pane" @kctx_display 2>/dev/null)" || display=""
    if [[ -z "$display" ]]; then
        display="$(tmux show-options -pqv -t "$pane" @kctx_context 2>/dev/null)" || display=""
    fi
    printf '%s' "$display"
}

# The pane's selection:view pair, which is what now points at the new context.
# Read-only, and empty unless an explicit override is active on the pane.
pane_pair() {
    local pane="$1"
    local pair

    pair="$("$KCTX_BIN" runtime override "$pane" 2>/dev/null)" || pair=""
    printf '%s' "$pair"
}

# The KUBECONFIG the claude process was executed with. /proc holds the exec-time
# environment, so this proves the launch binding and nothing later: a session
# that never inherited the pair cannot see the swap under any circumstances.
launch_kubeconfig() {
    local pid="$1"
    local environ="${PROC_DIR}/${pid}/environ"

    [[ -r "$environ" ]] || return 0
    tr '\0' '\n' <"$environ" 2>/dev/null |
        grep -a '^KUBECONFIG=' |
        head -1 |
        cut -d= -f2- || true
}

# Report the change, then hand the agent a check it can run and a path it can
# use. Never claim the swap already reached its tool calls.
compose_message() {
    local connection="$1"
    local pair="$2"
    local launch_kubeconfig="$3"

    if [[ -z "$connection" ]]; then
        printf '%s' "[kctx] The kubernetes context override on this pane was released, so KUBECONFIG follows direnv again. Confirm with 'kubectl config current-context' before acting on any cluster, and treat earlier cluster output as stale."
        return 0
    fi

    if [[ -n "$pair" && -n "$launch_kubeconfig" && "$launch_kubeconfig" != "$pair" ]]; then
        printf '%s' "[kctx] This pane's kubernetes context is now ${connection}, but this session launched with KUBECONFIG=${launch_kubeconfig} instead of the pane kubeconfig, so the swap does NOT reach your tool calls. Run kubectl as 'KUBECONFIG=${pair} kubectl ...', or restart the session to inherit the pane. Treat earlier cluster output as stale."
        return 0
    fi

    if [[ -n "$pair" ]]; then
        printf '%s' "[kctx] This pane's kubernetes context is now ${connection}, and the pane kubeconfig pointing at it is ${pair}. Your Bash calls are fresh shells whose KUBECONFIG your profile or direnv can override, so confirm with 'kubectl config current-context' before acting; if it disagrees, run kubectl as 'KUBECONFIG=${pair} kubectl ...'. Treat earlier cluster output as stale."
        return 0
    fi

    printf '%s' "[kctx] This pane's kubernetes context is now ${connection}. Your Bash calls are fresh shells whose KUBECONFIG your profile or direnv can override, so confirm with 'kubectl config current-context' before acting on any cluster. Treat earlier cluster output as stale."
}

send_to_pane() {
    local pane="$1"
    local message="$2"

    # copy-mode swallows send-keys, so leave it first. Errors when the pane is
    # not in copy-mode, which is the normal case.
    tmux send-keys -t "$pane" -X cancel 2>/dev/null || true
    tmux send-keys -t "$pane" -l "$message" || return 1
    sleep "$ENTER_DELAY"
    tmux send-keys -t "$pane" Enter || return 1
}

main() {
    local pane="${1:-}"

    if [[ -z "$pane" ]]; then
        usage
        exit 1
    fi
    if [[ ! "$pane" =~ ^%[0-9]+$ ]]; then
        echo "Error: invalid pane id: $pane" >&2
        exit 1
    fi

    local claude_pid
    claude_pid="$(pane_claude_pid "$pane")" || exit 0
    [[ -n "$claude_pid" ]] || exit 0

    local connection pair launch message
    connection="$(current_connection "$pane")"
    pair="$(pane_pair "$pane")"
    launch="$(launch_kubeconfig "$claude_pid")"
    message="$(compose_message "$connection" "$pair" "$launch")"

    sleep "$SETTLE_DELAY"
    send_to_pane "$pane" "$message"
}

main "$@"
