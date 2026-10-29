#!/usr/bin/env bats
# Shell fragments expand in the child zsh, not in Bats.
# shellcheck disable=SC2016

# Exercise the hand-started entry points without launching an agent or touching tmux.
setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    export HOME="$BATS_TEST_TMPDIR/home"
    export LAUNCH_LOG="$BATS_TEST_TMPDIR/launch"
    mkdir -p "$HOME/bin" "$HOME/.codex/scripts" "$HOME/dev/dotfiles/scripts"
    touch "$HOME/dev/dotfiles/scripts/__reusable_variables.sh"
    export PATH="$HOME/bin:$PATH"
    cat > "$HOME/bin/__claude_with_monitor.sh" <<'EOF'
#!/bin/sh
printf '%s\n' launcher "$PWD" "$@" > "$LAUNCH_LOG"
EOF
    cat > "$HOME/.codex/scripts/__codex_with_app_server.sh" <<'EOF'
#!/bin/sh
printf '%s\n' app-server "$@" > "$LAUNCH_LOG"
EOF
    cat > "$HOME/bin/claude" <<'EOF'
#!/bin/sh
printf '%s\n' raw-cli "$@" > "$LAUNCH_LOG"
EOF
    chmod +x "$HOME/bin/"* "$HOME/.codex/scripts/"*.sh
}

# Capture the launch command. The detached UI poll exits on its first sleep.
run_widget() {
    run timeout 10 zsh -f -c '
        source "$REPO_ROOT/.zsh_claude"
        zle() { :; }
        sleep() { exit 0; }
        mktemp() { command mktemp "$HOME/prompt.XXXXXX"; }
        tmux() {
            case "$1" in
                display-message) print -r -- %999 ;;
                send-keys) printf "%s\n" "$@" > "$LAUNCH_LOG" ;;
            esac
        }
        BUFFER="printf widget-output"
        "$1"
    ' zsh "$1"
}

@test "command widget launches through the channels-enabled wrapper" {
    run_widget execute_and_claude
    [ "$status" -eq 0 ]
    [ "$(cat "$LAUNCH_LOG")" = "$(printf '%s\n' send-keys -t %999 \
        'KUBECONFIG=/home/decoder/dev/homelab/kubeconfig __claude_with_monitor.sh' C-m)" ]
}

@test "template widget launches through the channels-enabled wrapper" {
    run_widget claude_prompt
    [ "$status" -eq 0 ]
    [ "$(cat "$LAUNCH_LOG")" = "$(printf '%s\n' send-keys -t %999 \
        'KUBECONFIG=/home/decoder/dev/homelab/kubeconfig __claude_with_monitor.sh' C-m)" ]
}

@test "bookmark resume uses the wrapper without relying on aliases" {
    mkdir -p "$HOME/project with spaces"
    run timeout 10 zsh -f -c '
        compdef() { :; }
        source "$REPO_ROOT/.zsh_functions"
        python3() { printf "%s\t%s\n" "$HOME/project with spaces" bookmark-session; }
        cs saved
    '
    [ "$status" -eq 0 ]
    [ "$(cat "$LAUNCH_LOG")" = "$(printf '%s\n' launcher \
        "$HOME/project with spaces" --resume bookmark-session)" ]
}

@test "plain Claude alias preserves caller arguments through the wrapper" {
    run timeout 10 zsh -f -c 'source "$REPO_ROOT/.zsh_aliases"; eval "$1"' \
        zsh 'claude -- "prompt with spaces"'
    [ "$status" -eq 0 ]
    [ "$(cat "$LAUNCH_LOG")" = "$(printf '%s\n' launcher "$PWD" -- 'prompt with spaces')" ]
}

@test "plain Codex uses its bus-enabled app-server wrapper" {
    run timeout 10 zsh -f -c 'source "$REPO_ROOT/.zsh_claude"; eval "$1"' \
        zsh 'codex resume "session with spaces"'
    [ "$status" -eq 0 ]
    [ "$(cat "$LAUNCH_LOG")" = "$(printf '%s\n' app-server resume 'session with spaces')" ]
}
