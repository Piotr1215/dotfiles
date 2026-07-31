#!/usr/bin/env bash
# Tell a Claude session running in a tmux pane that the pane's kubernetes
# connection just changed.
#
# kctx pins each pane's KUBECONFIG to a stable runtime path and rewrites the
# selection in place, so a swap is already live for a process that is running:
# the next kubectl a Claude session shells out to hits the new cluster. Claude
# has no way to notice. Nothing re-reads the environment mid-session, the pane
# border is not in its context, and the shell hook that would reassert the pair
# cannot run while claude holds the pane. Left alone it keeps reasoning about
# the old cluster until a command returns something that makes no sense.
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

usage() {
    echo "Usage: $(basename "$0") <pane-id>" >&2
    echo "  pane-id: tmux pane id, e.g. %33" >&2
}

# True when a claude process lives anywhere under the pane's process tree.
# claude is rarely the pane process itself: the pane holds a shell, and claude
# sits below it, sometimes under the __claude_with_monitor.sh wrapper. One ps
# snapshot walked upwards beats recursing with a process call per level.
pane_runs_claude() {
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
                    if (p == root) exit 0
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

    pane_runs_claude "$pane" || exit 0

    local connection message
    connection="$(current_connection "$pane")"
    if [[ -n "$connection" ]]; then
        message="[kctx] Your kubernetes context has been swapped to ${connection}. This pane's KUBECONFIG already points at it, so treat any earlier cluster output as stale."
    else
        message="[kctx] The kubernetes context override on this pane was released, so KUBECONFIG follows direnv again. Treat any earlier cluster output as stale."
    fi

    sleep "$SETTLE_DELAY"
    send_to_pane "$pane" "$message"
}

main "$@"
