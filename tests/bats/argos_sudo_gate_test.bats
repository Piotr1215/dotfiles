#!/usr/bin/env bats

setup() {
    bats_require_minimum_version 1.5.0
    applet="$BATS_TEST_DIRNAME/../../.config/argos/sudo-gate.1s.sh"
    export SUDO_GATE_PENDING_DIR="$BATS_TEST_TMPDIR/pending"
    export SUDO_GATE_TEST_MODE=1 SUDO_GATE_TEST_COMM=sleep
    mkdir -p "$SUDO_GATE_PENDING_DIR"
    sleep 300 &
    sleeper=$!
}

teardown() {
    kill "$sleeper" 2>/dev/null || true
    wait "$sleeper" 2>/dev/null || true
}

record() {
    local pid="$1" timestamp="${2:-$(date +%s)}"
    jq -n --argjson ts "$timestamp" --argjson pid "$pid" '{ts:$ts,sudo_pid:$pid,command:"sudo echo <hello> | cat",cwd:"/tmp",detection:"agent",agent:"worker",session:"work",pane:"%1"}' >"$SUDO_GATE_PENDING_DIR/$pid.json"
}

@test "empty and dead requests are hidden" {
    run "$applet"
    [ "$status" -eq 0 ]
    [ "$output" = '---' ]
    record 99999999
    run "$applet"
    [ "$output" = '---' ]
}

@test "live requests show escaped details and refusal action" {
    record "$sleeper"
    run "$applet"
    [ "$status" -eq 0 ]
    [[ "$output" == *'🔑 ROOT worker:'* ]]
    [[ "$output" == *'sudo echo &lt;hello&gt; &#124; cat'* ]]
    [[ "$output" == *'work / %1'* ]]
    [[ "$output" == *'Touch the YubiKey to run exactly this command.'* ]]
    [[ "$output" == *'--refuse'* ]]
}

@test "stale and malformed records are hidden" {
    record "$sleeper" "$(( $(date +%s) - 120 ))"
    printf '{broken' >"$SUDO_GATE_PENDING_DIR/broken.json"
    run "$applet"
    [ "$output" = '---' ]
}

@test "missing context is shown as unknown" {
    jq -n --argjson ts "$(date +%s)" --argjson pid "$sleeper" '{ts:$ts,sudo_pid:$pid,command:"sudo id",detection:"agent",agent:"worker",session:"",pane:null}' >"$SUDO_GATE_PENDING_DIR/$sleeper.json"
    run "$applet"
    [ "$status" -eq 0 ]
    [[ "$output" == *'🔑 ROOT worker:'* ]]
    [[ "$output" == *'Session / pane: unknown / unknown'* ]]
    [[ "$output" == *'Cwd: unknown'* ]]
}

@test "multiple live requests appear and refusal stops only its target" {
    sleep 300 &
    second=$!
    record "$sleeper"
    record "$second"
    run "$applet"
    [ "$(printf '%s\n' "$output" | grep -c '^Command:')" -eq 2 ]
    run "$applet" --refuse "$second"
    [ "$status" -eq 0 ]
    wait "$second" || true
    run ! kill -0 "$second"
    kill -0 "$sleeper"
}

@test "a request with a child is hidden" {
    bash -c 'sleep 300 & wait' &
    parent=$!
    for _ in {1..50}; do
        [ -s "/proc/$parent/task/$parent/children" ] && break
        sleep 0.01
    done
    child=$(cat "/proc/$parent/task/$parent/children")
    export SUDO_GATE_TEST_COMM=bash
    record "$parent"
    run "$applet"
    kill "$child" "$parent" 2>/dev/null || true
    wait "$parent" 2>/dev/null || true
    [ "$output" = '---' ]
}
