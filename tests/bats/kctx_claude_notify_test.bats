#!/usr/bin/env bats

# Test suite for __kctx_claude_notify.sh
#
# The script has three jobs: decide whether a tmux pane holds a claude process,
# work out whether the swap can actually reach that process, and type an honest
# account of the change into the pane. All of it runs against mocked tmux, ps,
# kctx and /proc, so the tests never touch the live tmux server.

SCRIPT="/home/decoder/dev/dotfiles/scripts/__kctx_claude_notify.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    export PATH="${TEST_DIR}:${PATH}"

    # Sending is instant in tests; the real delays only matter on a live TUI.
    export KCTX_NOTIFY_SETTLE_DELAY=0
    export KCTX_NOTIFY_ENTER_DELAY=0

    TMUX_LOG="${TEST_DIR}/tmux_calls.log"
    export TMUX_LOG

    # Mocked tmux: logs every call, answers the two queries the script makes.
    # Pane options come from the environment so each test can shape them.
    cat > "${TEST_DIR}/tmux" << 'EOF'
#!/usr/bin/env bash
echo "$*" >> "${TMUX_LOG}"
case "$1" in
    display-message)
        echo "${MOCK_PANE_PID:-1000}"
        ;;
    show-options)
        case "$*" in
            *@kctx_display*) printf '%s\n' "${MOCK_KCTX_DISPLAY:-}" ;;
            *@kctx_context*) printf '%s\n' "${MOCK_KCTX_CONTEXT:-}" ;;
        esac
        ;;
    send-keys)
        exit 0
        ;;
esac
exit 0
EOF
    chmod +x "${TEST_DIR}/tmux"

    # Mocked ps: prints a process table fixture as "pid ppid comm".
    cat > "${TEST_DIR}/ps" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "${MOCK_PS_TABLE:-}"
EOF
    chmod +x "${TEST_DIR}/ps"

    # Mocked kctx: `runtime override <pane>` prints the pane pair, and fails the
    # way the real binary does when no override is active.
    cat > "${TEST_DIR}/kctx" << 'EOF'
#!/usr/bin/env bash
if [[ -z "${MOCK_KCTX_PAIR:-}" ]]; then
    echo "Error: no pane override is active" >&2
    exit 1
fi
printf '%s\n' "${MOCK_KCTX_PAIR}"
EOF
    chmod +x "${TEST_DIR}/kctx"

    # Mocked /proc: the exec-time environment of the claude process.
    export KCTX_NOTIFY_PROC_DIR="${TEST_DIR}/proc"

    # Default table: pane shell 1000 -> claude 1001.
    export MOCK_PS_TABLE=$'1000 999 zsh\n1001 1000 claude'
    export MOCK_PANE_PID=1000
    export MOCK_KCTX_DISPLAY="loft-prod/eng"
    export MOCK_KCTX_CONTEXT="gke::loft-prod/europe-west1/loft-prod-engineering"
    export MOCK_KCTX_PAIR="/run/user/1000/kctx/abc123/selection.yaml:/run/user/1000/kctx/abc123/view.yaml"

    # By default the session inherited the pane pair, the healthy launch case.
    write_proc_env 1001 "$MOCK_KCTX_PAIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Write a NUL-separated environ fixture for a pid, as /proc exposes it.
write_proc_env() {
    local pid="$1"
    local kubeconfig="$2"

    mkdir -p "${KCTX_NOTIFY_PROC_DIR}/${pid}"
    printf 'PATH=/usr/bin\0KUBECONFIG=%s\0TMUX_PANE=%%33\0' "$kubeconfig" \
        > "${KCTX_NOTIFY_PROC_DIR}/${pid}/environ"
}

# Extract the literal text the script typed into the pane.
sent_text() {
    grep '^send-keys .* -l ' "$TMUX_LOG" | sed 's/^.* -l //'
}

@test "fails without a pane id" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "rejects a malformed pane id" {
    run "$SCRIPT" "not-a-pane"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid pane id"* ]]
}

@test "rejects a pane id that is a shell metacharacter payload" {
    run "$SCRIPT" '%1; rm -rf /'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid pane id"* ]]
}

@test "notifies a claude session running under the pane shell" {
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    run sent_text
    [[ "$output" == *"context is now loft-prod/eng"* ]]
    grep -q '^send-keys -t %33 Enter$' "$TMUX_LOG"
}

@test "finds claude nested under the monitor wrapper" {
    export MOCK_PS_TABLE=$'1000 999 zsh\n1001 1000 bash\n1002 1001 claude'
    write_proc_env 1002 "$MOCK_KCTX_PAIR"
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    run sent_text
    [[ "$output" == *"context is now loft-prod/eng"* ]]
}

@test "detects claude launched directly as the pane process" {
    export MOCK_PS_TABLE=$'1000 999 claude'
    write_proc_env 1000 "$MOCK_KCTX_PAIR"
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    run sent_text
    [[ "$output" == *"context is now"* ]]
}

@test "stays silent when the pane runs no claude" {
    export MOCK_PS_TABLE=$'1000 999 zsh\n1001 1000 vim'
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    run grep -c 'send-keys' "$TMUX_LOG"
    [ "$output" -eq 0 ]
}

@test "ignores a claude process in an unrelated pane" {
    export MOCK_PS_TABLE=$'1000 999 zsh\n2000 999 zsh\n2001 2000 claude'
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    run grep -c 'send-keys' "$TMUX_LOG"
    [ "$output" -eq 0 ]
}

@test "falls back to the raw context when no display alias exists" {
    export MOCK_KCTX_DISPLAY=""
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    run sent_text
    [[ "$output" == *"context is now gke::loft-prod/europe-west1/loft-prod-engineering"* ]]
}

@test "reports a release when the pane has no connection left" {
    export MOCK_KCTX_DISPLAY=""
    export MOCK_KCTX_CONTEXT=""
    export MOCK_KCTX_PAIR=""
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    run sent_text
    [[ "$output" == *"was released"* ]]
    [[ "$output" == *"direnv"* ]]
    [[ "$output" == *"current-context"* ]]
}

@test "never claims the swap already reached the agent" {
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    run sent_text
    [[ "$output" != *"already points at it"* ]]
}

@test "names the pane kubeconfig and asks for a verification command" {
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    run sent_text
    [[ "$output" == *"kubectl config current-context"* ]]
    [[ "$output" == *"KUBECONFIG=${MOCK_KCTX_PAIR} kubectl"* ]]
}

@test "says the swap does not reach a session launched off the pane pair" {
    # The observed failure: a worktree .envrc exported KUBECONFIG, so claude
    # launched on that file and every tool call resolves the old cluster.
    write_proc_env 1001 "/home/decoder/dev/homelab/kubeconfig"
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    run sent_text
    [[ "$output" == *"does NOT reach your tool calls"* ]]
    [[ "$output" == *"KUBECONFIG=/home/decoder/dev/homelab/kubeconfig"* ]]
    [[ "$output" == *"KUBECONFIG=${MOCK_KCTX_PAIR} kubectl"* ]]
}

@test "still reports the change when the launch environment is unreadable" {
    rm -rf "${KCTX_NOTIFY_PROC_DIR}/1001"
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    run sent_text
    [[ "$output" == *"context is now loft-prod/eng"* ]]
    [[ "$output" != *"does NOT reach"* ]]
}

@test "still reports the change when kctx cannot name the pane pair" {
    export MOCK_KCTX_PAIR=""
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    run sent_text
    [[ "$output" == *"context is now loft-prod/eng"* ]]
    [[ "$output" == *"kubectl config current-context"* ]]
}

@test "leaves copy-mode before typing" {
    run "$SCRIPT" "%33"
    [ "$status" -eq 0 ]
    grep -q '^send-keys -t %33 -X cancel$' "$TMUX_LOG"
    # cancel must precede the text, or the keystrokes land in the copy buffer.
    cancel_line=$(grep -n -- '-X cancel' "$TMUX_LOG" | cut -d: -f1)
    text_line=$(grep -n -- ' -l ' "$TMUX_LOG" | cut -d: -f1)
    [ "$cancel_line" -lt "$text_line" ]
}
