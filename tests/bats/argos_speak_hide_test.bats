#!/usr/bin/env bats

setup() {
    argos="$BATS_TEST_DIRNAME/../../.config/argos"
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$XDG_RUNTIME_DIR" "$HOME" "$BATS_TEST_TMPDIR/bin"
    touch "$XDG_RUNTIME_DIR/speak-mode"
    ln -s "$(command -v bash)" "$BATS_TEST_TMPDIR/bin/bash"
    ln -s "$(command -v python3)" "$BATS_TEST_TMPDIR/bin/python3"
    for cmd in systemctl ykman id curl date cat jq; do
        printf '#!/bin/bash\nprintf "unexpected command: %%s\\n" "$0" >&2\nexit 99\n' >"$BATS_TEST_TMPDIR/bin/$cmd"
        chmod +x "$BATS_TEST_TMPDIR/bin/$cmd"
    done
}

@test "presenting applets emit only the Argos hiding separator before doing work" {
    for applet in claude.30s.sh cron-status.1m.sh notion-mic.1s.sh power-mode.30s.sh \
                  reminders.30s.sh services-status.5m.py totp.1s.sh; do
        run env PATH="$BATS_TEST_TMPDIR/bin" "$argos/$applet"
        [ "$status" -eq 0 ] || { echo "$applet: $output"; return 1; }
        [ "$output" = '---' ] || { echo "$applet: unexpected output: $output"; return 1; }
    done
    [ -z "$(ls -A "$HOME")" ]
}

@test "system, hardware and weather applets have no speak-mode guard" {
    for applet in system.1l.1s.sh hwmon.2l.10s.sh weather.30m.py; do
        ! grep -q 'speak-mode' "$argos/$applet"
    done
}
