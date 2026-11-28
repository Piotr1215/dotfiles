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
    [[ "$output" == *"color='#888888'"* ]]
    record 99999999
    run "$applet"
    [[ "$output" == *"color='#888888'"* ]]
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
    [[ "$output" == *"color='#ff4444'"* ]]
    [[ "$output" == *'Do not touch'* ]]
    [[ "$output" == *'Allowed for agents (no touch)'* ]]
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
    record "$parent"
    run env SUDO_GATE_TEST_COMM=bash "$applet"
    kill "$child" "$parent" 2>/dev/null || true
    wait "$parent" 2>/dev/null || true
    [[ "$output" == *"color='#888888'"* ]]
}

@test "idle label and allow rules remain visible" {
    export SUDO_GATE_RULES_FILE="$BATS_TEST_TMPDIR/allow"
    printf '%s\n' '{"kind":"program","path":"/usr/bin/id","added":"now","note":"test"}' >"$SUDO_GATE_RULES_FILE"
    run "$applet"
    [ "$status" -eq 0 ]
    [[ "$output" == *"color='#888888'"* ]]
    [[ "$(head -1 <<<"$output")" == "<tt><b>SU:</b></tt><tt><span color='#888888'>0</span></tt> | font='monospace' size="* ]]
    [[ "$output" == *'Allowed for agents (no touch)'* ]]
    [[ "$output" == *'/usr/bin/id'* ]]
    [[ "$output" == *'sudo-agent-gate remove 1'* ]]
}

@test "live request offers allow actions and recent entries" {
    export SUDO_GATE_RECENT_FILE="$BATS_TEST_TMPDIR/recent.jsonl"
    record "$sleeper"
    jq '. + {program:"/usr/bin/id",argv:["id","-u"]}' "$SUDO_GATE_PENDING_DIR/$sleeper.json" >"$BATS_TEST_TMPDIR/record"
    mv "$BATS_TEST_TMPDIR/record" "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    printf '%s\n' '{"agent":"worker","command":"id -u"}' >"$SUDO_GATE_RECENT_FILE"
    run "$applet"
    [[ "$output" == *"Always allow id for agents"* ]]
    [[ "$output" == *"allow-program-from $sleeper"* ]]
    [[ "$output" == *"allow-exact-from $sleeper"* ]]
    [[ "$output" == *'Applies from the next call; touch or refuse this one.'* ]]
    [[ "$output" == *'auto-allowed: worker id -u'* ]]
}

@test "busy check shares request liveness" {
    run "$applet" --busy
    [ "$status" -eq 1 ]
    record "$sleeper"
    run "$applet" --busy
    [ "$status" -eq 0 ]
}

@test "old live request with matching process start remains visible and busy" {
    record "$sleeper" "$(( $(date +%s) - 300 ))"
    start=$(awk '{print $22}' "/proc/$sleeper/stat")
    jq --arg start "$start" '.start_time=$start' "$SUDO_GATE_PENDING_DIR/$sleeper.json" >"$BATS_TEST_TMPDIR/record"
    mv "$BATS_TEST_TMPDIR/record" "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    run "$applet"
    [[ "$output" == *'🔑 ROOT worker:'* ]]
    run "$applet" --busy
    [ "$status" -eq 0 ]
}

@test "reused pid with a different start token is ignored" {
    record "$sleeper"
    jq '.start_time="1"' "$SUDO_GATE_PENDING_DIR/$sleeper.json" >"$BATS_TEST_TMPDIR/record"
    mv "$BATS_TEST_TMPDIR/record" "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    run "$applet" --busy
    [ "$status" -eq 1 ]
}

@test "a gate helper child remains visible and blocks unlocks" {
    bash -c 'bash -c "exec -a /usr/local/sbin/sudo-agent-gate sleep 300" & wait' &
    parent=$!
    for _ in {1..50}; do
        [ -s "/proc/$parent/task/$parent/children" ] && break
        sleep 0.01
    done
    child=$(cat "/proc/$parent/task/$parent/children")
    record "$parent"
    run env SUDO_GATE_TEST_COMM=bash "$applet" --busy
    result=$status
    kill "$child" "$parent" 2>/dev/null || true
    wait "$parent" 2>/dev/null || true
    [ "$result" -eq 0 ]
}

@test "a reaped-pending zombie child remains visible and busy" {
    python3 -c 'import os,time; child=os.fork(); child and time.sleep(300)' >/dev/null 2>&1 &
    parent=$!
    child=""
    for _ in {1..100}; do
        child=$(cat "/proc/$parent/task/$parent/children" 2>/dev/null || :)
        [[ -n "$child" && -r "/proc/$child/stat" ]] && [[ "$(awk '{print $3}' "/proc/$child/stat")" == Z ]] && break
        sleep 0.01
    done
    [ -n "$child" ]
    record "$parent"
    run env SUDO_GATE_TEST_COMM=python3 "$applet" --busy
    result=$status
    kill "$parent" 2>/dev/null || true
    wait "$parent" 2>/dev/null || true
    [ "$result" -eq 0 ]
}

@test "exact argv rule renders with its one-based remove action" {
    export SUDO_GATE_RULES_FILE="$BATS_TEST_TMPDIR/allow"
    printf '%s\n' '{"kind":"program","path":"/usr/bin/id","added":"now","note":"first"}' '{"kind":"exact","argv":["/usr/bin/printf","hello world"],"added":"now","note":"second"}' >"$SUDO_GATE_RULES_FILE"
    run "$applet"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'/usr/bin/printf &#x27;hello world&#x27; | font=monospace\n--Remove | bash=\'sudo -n /usr/local/sbin/sudo-agent-gate remove 2\''* ]]
}

@test "recent history renders only the last five entries in order" {
    export SUDO_GATE_RECENT_FILE="$BATS_TEST_TMPDIR/recent.jsonl"
    for number in {1..7}; do
        jq -nc --arg n "$number" '{agent:("worker"+$n),command:("command"+$n)}' >>"$SUDO_GATE_RECENT_FILE"
    done
    run "$applet"
    [ "$status" -eq 0 ]
    recent=$(printf '%s\n' "$output" | rg '^auto-allowed:')
    expected=$(printf 'auto-allowed: worker%s command%s | font=monospace\n' 3 3 4 4 5 5 6 6 7 7)
    [ "$recent" = "$expected" ]
}

@test "future timestamp with matching process start stays visible and clamps age" {
    record "$sleeper" "$(( $(date +%s) + 300 ))"
    start=$(awk '{print $22}' "/proc/$sleeper/stat")
    jq --arg start "$start" '.start_time=$start' "$SUDO_GATE_PENDING_DIR/$sleeper.json" >"$BATS_TEST_TMPDIR/record"
    mv "$BATS_TEST_TMPDIR/record" "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    run "$applet"
    [[ "$output" == *'🔑 ROOT worker:'* ]]
    [[ "$output" == *'Age: 0s'* ]]
    run "$applet" --busy
    [ "$status" -eq 0 ]
}

@test "legacy future timestamp stays hidden" {
    record "$sleeper" "$(( $(date +%s) + 300 ))"
    run "$applet" --busy
    [ "$status" -eq 1 ]
}

@test "broken record for live pid makes state unknown but dead pid stays clear" {
    ln -s "$BATS_TEST_TMPDIR/missing" "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    run "$applet" --busy
    [ "$status" -eq 2 ]
    run "$applet"
    [[ "$output" == *"color='#ff4444'"* ]]
    [[ "$output" == *'Do not touch'* ]]
    [[ "$output" == *'Allowed for agents (no touch)'* ]]
    rm "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    ln -s "$BATS_TEST_TMPDIR/missing" "$SUDO_GATE_PENDING_DIR/99999999.json"
    run "$applet" --busy
    [ "$status" -eq 1 ]
}

@test "missing proc attribute for live pid is unknown" {
    export SUDO_GATE_TEST_PROC_ROOT="$BATS_TEST_TMPDIR/proc"
    mkdir -p "$SUDO_GATE_TEST_PROC_ROOT/$sleeper"
    record "$sleeper"
    run "$applet" --busy
    [ "$status" -eq 2 ]
    run "$applet"
    [[ "$output" == *'Do not touch'* ]]
}

@test "unknown state suppresses touch instructions even with a live request" {
    record "$sleeper"
    printf '{broken' >"$SUDO_GATE_PENDING_DIR/broken.json"
    run "$applet"
    [[ "$output" == *'ROOT state unavailable'* ]]
    [[ "$output" == *'Command:'* ]]
    [[ "$output" != *'Touch the YubiKey to run exactly this command.'* ]]
    [[ "$output" == *'Allowed for agents (no touch)'* ]]
    run "$applet" --busy
    [ "$status" -eq 2 ]
}
