#!/usr/bin/env bats
# Tests for scripts/__igc_resume_hook.sh

HOOK="$BATS_TEST_DIRNAME/../../scripts/__igc_resume_hook.sh"

setup() {
    STUBS="$(mktemp -d)"
    CALLS="$STUBS/calls"
    # A fake /sys/module/igc says the driver is loaded; modprobe only records its args.
    mkdir "$STUBS/igc"
    export IGC_MODULE_DIR="$STUBS/igc"
    printf '#!/usr/bin/env bash\necho "modprobe $*" >>"%s"\n' "$CALLS" >"$STUBS/modprobe"
    chmod +x "$STUBS/modprobe"
    export PATH="$STUBS:$PATH"
}

teardown() {
    rm -rf "$STUBS"
}

@test "post unloads then reloads igc" {
    run "$HOOK" post suspend
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "$(printf 'modprobe -r igc\nmodprobe igc')" ]
}

@test "post does nothing when igc is not loaded" {
    IGC_MODULE_DIR="$STUBS/absent" run "$HOOK" post suspend
    [ "$status" -eq 0 ]
    [ ! -e "$CALLS" ]
}

@test "pre leaves the driver alone" {
    run "$HOOK" pre suspend
    [ "$status" -eq 0 ]
    [ ! -e "$CALLS" ]
}

@test "unknown phase exits 1 with usage" {
    run "$HOOK" bogus
    [ "$status" -eq 1 ]
    [[ "$output" == usage:* ]]
}

@test "install creates the hook directory and copies an executable hook" {
    IGC_HOOK_PATH="$STUBS/new-dir/igc-resume" run "$HOOK" install
    [ "$status" -eq 0 ]
    [ -x "$STUBS/new-dir/igc-resume" ]
    cmp -s "$HOOK" "$STUBS/new-dir/igc-resume"
}
