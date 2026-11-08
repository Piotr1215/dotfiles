#!/usr/bin/env bats
# The one-second system applet and the 10s hwmon applet read GPU numbers from
# the resource watcher's current.json instead of forking nvidia-smi. Each
# nvidia-smi run re-initialised the driver and spiked the GPU on an idle desk
# (2026-11-09). nvidia-smi stays as the fallback for a missing or stale file.

ARGOS="$(cd "$BATS_TEST_DIRNAME/../../.config/argos" && pwd)"

setup() {
    command -v jq >/dev/null || skip "jq not installed"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/bin"
    # A stub nvidia-smi that records each call and answers like the real one
    # for both applets' queries.
    cat >"$WORK/bin/nvidia-smi" <<EOF
#!/usr/bin/env bash
echo called >>"$WORK/nvidia-smi.calls"
case "\$*" in
    *utilization.gpu,memory.used*) echo "77, 2048, 12227" ;;
    *temperature.gpu*) echo "66" ;;
    *power.draw*) echo "33.30" ;;
esac
EOF
    chmod +x "$WORK/bin/nvidia-smi"
    export PATH="$WORK/bin:$PATH"
    export RESOURCE_WATCHER_STATE="$WORK/current.json"
    echo '{"gpu":{"temperature_c":51,"power_w":14.54,"vram_used_mib":1109.3,"vram_total_mib":12227.0,"utilization_percent":12}}' >"$RESOURCE_WATCHER_STATE"
}

teardown() {
    rm -rf "$WORK"
}

calls() {
    [[ -f "$WORK/nvidia-smi.calls" ]] && wc -l <"$WORK/nvidia-smi.calls" || echo 0
}

@test "system applet reads a fresh watcher file and never runs nvidia-smi" {
    run bash "$ARGOS/system.1l.1s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *" 12%"* ]]
    [[ "$output" == *" 1.1G"* ]]
    [ "$(calls)" -eq 0 ]
}

@test "system applet falls back to nvidia-smi when the watcher file is stale" {
    touch -d '-1 minute' "$RESOURCE_WATCHER_STATE"
    run bash "$ARGOS/system.1l.1s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *" 77%"* ]]
    [[ "$output" == *" 2.0G"* ]]
    [ "$(calls)" -eq 1 ]
}

@test "system applet falls back to nvidia-smi when the watcher file is missing" {
    rm -f "$RESOURCE_WATCHER_STATE"
    run bash "$ARGOS/system.1l.1s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *" 77%"* ]]
    [ "$(calls)" -eq 1 ]
}

@test "system applet shows N/A when the watcher has no GPU" {
    echo '{"gpu":null}' >"$RESOURCE_WATCHER_STATE"
    run bash "$ARGOS/system.1l.1s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"N/A"* ]]
    [ "$(calls)" -eq 0 ]
}

@test "hwmon applet reads GPU temp and power from a fresh watcher file" {
    run bash "$ARGOS/hwmon.2l.10s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"51°C"* ]]
    [[ "$output" == *"14"*W* ]]
    [ "$(calls)" -eq 0 ]
}

@test "hwmon applet falls back to nvidia-smi when the watcher file is stale" {
    touch -d '-1 minute' "$RESOURCE_WATCHER_STATE"
    run bash "$ARGOS/hwmon.2l.10s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"66°C"* ]]
    [ "$(calls)" -eq 2 ]
}
