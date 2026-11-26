#!/usr/bin/env bats
# The one-second system applet shows the system76-power profile. GNOME's power
# menu does not follow switches made by cpu-profile-auto, so Piotr could not
# see Performance or Balanced change (26 Nov 2026). The applet asks the power
# daemon over D-Bus on every refresh, about 2 ms, instead of the 8 ms CLI.

ARGOS="$(cd "$BATS_TEST_DIRNAME/../../.config/argos" && pwd)"

setup() {
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/bin"
    cat >"$WORK/bin/busctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$WORK/busctl.calls"
[[ -n "\${TEST_PROFILE:-}" ]] || exit 1
printf 's "%s"\n' "\$TEST_PROFILE"
EOF
    chmod +x "$WORK/bin/busctl"
    export PATH="$WORK/bin:$PATH"
    export RESOURCE_WATCHER_STATE="$WORK/current.json"
    echo '{"gpu":{"vram_used_mib":1109.3,"utilization_percent":12}}' >"$RESOURCE_WATCHER_STATE"
}

teardown() {
    rm -rf "$WORK"
}

@test "Balanced shows B in green, read from the power daemon" {
    TEST_PROFILE=Balanced run bash "$ARGOS/system.1l.1s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"<b>PWR:</b></tt><tt><span color='#44ff44'>B</span>"* ]]
    [[ "$(cat "$WORK/busctl.calls")" == *"com.system76.PowerDaemon GetProfile"* ]]
}

@test "Performance shows P in orange" {
    TEST_PROFILE=Performance run bash "$ARGOS/system.1l.1s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"<span color='#ff9900'>P</span>"* ]]
}

@test "Battery shows E (eco) in cyan" {
    TEST_PROFILE=Battery run bash "$ARGOS/system.1l.1s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"<span color='#8be9fd'>E</span>"* ]]
}

@test "an unreachable daemon shows a grey question mark and keeps the line" {
    TEST_PROFILE= run bash "$ARGOS/system.1l.1s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"<span color='#666666'>?</span>"* ]]
    [[ "$output" == *"RAM:"* ]]
}
