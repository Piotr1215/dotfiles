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

# Run a widget with nvim stubbed to type a request, or to cancel when NVIM_RC is 1.
# The command widget leaves its next step in BUFFER, which the shell would run.
run_widget() {
    run timeout 10 zsh -f -c '
        source "$REPO_ROOT/.zsh_claude"
        zle() { :; }
        mktemp() { command mktemp "$HOME/prompt.XXXXXX"; }
        nvim() { (( ${NVIM_RC:-0} )) && return 1; print -r -- "my request" >> "${@[-1]}"; }
        BUFFER="printf widget-output"
        "$1"
        [[ "$1" == execute_and_claude ]] && eval "$BUFFER"
        ls "$HOME"/prompt.* 2>/dev/null && exit 9
        exit 0
    ' zsh "$1"
}

# The prompt the launcher got, after the -- that ends its options.
launched_prompt() {
    sed -n '4,$p' "$LAUNCH_LOG"
}

@test "command widget launches the wrapper with the command, output and request" {
    run_widget execute_and_claude
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "$LAUNCH_LOG")" = launcher ]
    [ "$(sed -n 3p "$LAUNCH_LOG")" = -- ]
    launched_prompt | grep -qx 'Command: printf widget-output'
    launched_prompt | grep -qx 'widget-output'
    launched_prompt | grep -qx 'my request'
}

@test "template widget launches the wrapper with the instructions and request" {
    run_widget claude_prompt
    [ "$status" -eq 0 ]
    launched_prompt | grep -qx 'User request below:'
    launched_prompt | grep -qx 'my request'
}

@test "quitting nvim with :cq launches nothing and removes the prompt file" {
    NVIM_RC=1 run_widget execute_and_claude
    [ "$status" -eq 0 ]
    [ ! -e "$LAUNCH_LOG" ]
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
