#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__kill_tmux_session.sh"
    TEST_BIN="${BATS_TEST_TMPDIR}/bin"
    TMUX_LOG="${BATS_TEST_TMPDIR}/tmux.log"
    mkdir -p "${TEST_BIN}"
    : > "${TMUX_LOG}"
    export TMUX_LOG

    # Fake tmux records every call and fails, so no test can reach a live server.
    cat > "${TEST_BIN}/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${TMUX_LOG}"
exit 1
EOF

    # Fake tmuxinator with projects dev and loft. dev renders DEV_RENDERS as its
    # session name, standing in for the `name:` field of dev.yml.
    cat > "${TEST_BIN}/tmuxinator" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list) printf 'tmuxinator projects:\ndev                   loft\n' ;;
    debug)
        name="$2"
        [ "$2" = "dev" ] && name="${DEV_RENDERS:-dev}"
        printf '  tmux new-session -d -s %s -n poke\n' "$name"
        ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "${TEST_BIN}/tmux" "${TEST_BIN}/tmuxinator"

    PATH="${TEST_BIN}:${PATH}"
    # shellcheck source=/dev/null
    source "${SCRIPT}"
}

@test "sourcing the script opens no picker and runs no tmux command" {
    [ ! -s "${TMUX_LOG}" ]
}

@test "routes through tmuxinator when the project renders the same session name" {
    DEV_RENDERS=dev run is_tmuxinator_session dev
    [ "${status}" -eq 0 ]
}

@test "skips tmuxinator when the project renders a different session name" {
    DEV_RENDERS=loft run is_tmuxinator_session dev
    [ "${status}" -ne 0 ]
}

@test "skips tmuxinator when the rendered name only starts with the session name" {
    DEV_RENDERS=dev-cloud run is_tmuxinator_session dev
    [ "${status}" -ne 0 ]
}

@test "skips tmuxinator for a session with no project file" {
    run is_tmuxinator_session homelab
    [ "${status}" -ne 0 ]
}
