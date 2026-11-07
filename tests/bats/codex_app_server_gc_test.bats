#!/usr/bin/env bats
# __codex_app_server_gc.sh runs from tmux's pane-exited hook. A failing kctx gc
# must not fail the hook (tmux shows "returned 1") or skip the app-server
# cleanup that follows it.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__codex_app_server_gc.sh"
    T="$(mktemp -d)"
    printf '#!/usr/bin/env bash\necho "Error: Could not open lock file" >&2\nexit 1\n' >"$T/kctx"
    chmod +x "$T/kctx"
    export KCTX_BIN="$T/kctx" KCTX_RUNTIME_ROOT="$T/runtime" CODEX_CONTROL_ROOT="$T/control"
    mkdir -p "$T/runtime" "$T/control/0123456789abcdef"
}

teardown() {
    rm -rf "$T"
}

@test "a failing kctx gc still exits 0" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"kctx runtime gc failed"* ]]
}

@test "a failing kctx gc still removes stale app-server state" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -d "$T/control/0123456789abcdef" ]
}
