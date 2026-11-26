#!/usr/bin/env bats
# The hwmon applet's T: colour follows the thermal target cpu-profile-auto
# holds (85 C on Balanced, 92 C on Performance since 26 Nov 2026). Piotr saw
# T:92C in red at the designed Performance target and worried; red now means
# the package is above its target by more than 2 C, so the cap is not holding.

ARGOS="$(cd "$BATS_TEST_DIRNAME/../../.config/argos" && pwd)"

setup() {
    WORK="$(mktemp -d)"
    export HWMON_THERMAL_FILE="$WORK/temp" HWMON_TCC_FILE="$WORK/tcc"
    export RESOURCE_WATCHER_STATE="$WORK/current.json"
    echo '{"gpu":{"temperature_c":51,"power_w":14.5}}' >"$RESOURCE_WATCHER_STATE"
}

teardown() {
    rm -rf "$WORK"
}

# t_color <celsius> <offset>: the colour of the panel's T: field.
t_color() {
    echo "$(( $1 * 1000 ))" >"$HWMON_THERMAL_FILE"
    echo "$2" >"$HWMON_TCC_FILE"
    run bash "$ARGOS/hwmon.2l.10s.sh"
    [ "$status" -eq 0 ]
    sed -n "s/.*<b>T:<\/b><\/tt><tt><span color='\([^']*\)'>$1C<.*/\1/p" <<<"$output" | head -1
}

@test "92 C at the Performance target is orange, not red" {
    [ "$(t_color 92 13)" = "#ff9900" ]
}

@test "95 C on Performance, above the target by 3 C, is red" {
    [ "$(t_color 95 13)" = "#ff4444" ]
}

@test "81 C on Performance is green" {
    [ "$(t_color 81 13)" = "#44ff44" ]
}

@test "88 C on Balanced, above its 85 C target by 3 C, is red" {
    [ "$(t_color 88 20)" = "#ff4444" ]
}

@test "an unreadable target falls back to the 92 C firmware target" {
    echo 92000 >"$HWMON_THERMAL_FILE"
    export HWMON_TCC_FILE="$WORK/missing"
    run bash "$ARGOS/hwmon.2l.10s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"<span color='#ff9900'>92C</span>"* ]]
}

# Fan speed, EPP and GPU power are effort, not danger, and no alert fires on
# them, so the dropdown stops them at orange (26 Nov 2026). GPU temperature
# keeps red above 80 C, the level where the watcher's gpu_hot alert fires.
@test "dropdown keeps red for GPU temperature only" {
    echo 92000 >"$HWMON_THERMAL_FILE"
    echo 13 >"$HWMON_TCC_FILE"
    echo 4500 >"$WORK/fan1"; echo 4800 >"$WORK/fan2"; echo performance >"$WORK/epp"
    export HWMON_FAN1_FILE="$WORK/fan1" HWMON_FAN2_FILE="$WORK/fan2" HWMON_EPP_FILE="$WORK/epp"
    echo '{"gpu":{"temperature_c":85,"power_w":160.2}}' >"$RESOURCE_WATCHER_STATE"
    run bash "$ARGOS/hwmon.2l.10s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CPU: 4500 RPM | size=10 color=#ff9900"* ]]
    [[ "$output" == *"GPU: 4800 RPM | size=10 color=#ff9900"* ]]
    [[ "$output" == *"EPP: performance | size=10 color=#ff9900"* ]]
    [[ "$output" == *"Power: 160.2W | size=10 color=#ff9900"* ]]
    [[ "$output" == *"Temp: 85°C | size=10 color=#ff4444"* ]]
}
