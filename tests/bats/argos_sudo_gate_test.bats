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
    [[ "$output" == *'Or touch the YubiKey to run exactly this command.'* ]]
    # Refuse is the first row under the label, bold and red, so it is easy to find.
    [[ "$(sed -n 3p <<<"$output")" == "<b>✕ Refuse this request</b> | bash='"*"--refuse $sleeper' terminal=false refresh=true color=#ff4444 size="* ]]
}

@test "stale and malformed records are hidden" {
    record "$sleeper" "$(( $(date +%s) - 120 ))"
    printf '{broken' >"$SUDO_GATE_PENDING_DIR/broken.json"
    run "$applet"
    [[ "$output" == *"color='#ff4444'"* ]]
    [[ "$output" == *'Do not touch'* ]]
    [[ "$output" == *'Edit allowed commands'* ]]
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

@test "idle label shows the edit row and never lists the rules" {
    # Piotr, 28 Nov: the list belongs in a file he edits, not in the menu.
    export SUDO_GATE_RULES_FILE="$BATS_TEST_TMPDIR/allow"
    printf '%s\n' '/usr/bin/id' >"$SUDO_GATE_RULES_FILE"
    run "$applet"
    [ "$status" -eq 0 ]
    [[ "$(head -1 <<<"$output")" == "<tt><b>SU:</b></tt><tt><span color='#888888'>0</span></tt> | font='monospace' size="* ]]
    [[ "$(sed -n 2p <<<"$output")" == '---' ]]
    [[ "$(sed -n 3p <<<"$output")" == "Edit allowed commands | bash='/usr/local/bin/tmux new-window -n sudo-allow $(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)/scripts/__sudo_gate_allow_edit.sh' terminal=false" ]]
    [[ "$output" != *'/usr/bin/id'* ]]
    [[ "$output" != *'Remove'* ]]
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
    [[ "$output" == *'Edit allowed commands'* ]]
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
    [[ "$output" != *'touch the YubiKey to run exactly this command.'* ]]
    [[ "$output" == *'Edit allowed commands'* ]]
    run "$applet" --busy
    [ "$status" -eq 2 ]
}

# The edit row's script: sudoedit, then the gate's check; the window waits for
# Enter only when something failed.
edit_env() {
    editor="$BATS_TEST_DIRNAME/../../scripts/__sudo_gate_allow_edit.sh"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" SUDO_GATE_ALLOW_FILE="$BATS_TEST_TMPDIR/allow" EDIT_LOG="$BATS_TEST_TMPDIR/edit.log"
    printf '#!/bin/sh\necho "sudoedit $SUDO_EDITOR $*" >>"$EDIT_LOG"\nexit "${SUDOEDIT_RC:-0}"\n' >"$BATS_TEST_TMPDIR/bin/sudoedit"
    printf '#!/bin/sh\necho "gate $*" >>"$EDIT_LOG"\n[ -z "$CHECK_FAIL" ] || { echo "line 3: bad" >&2; exit 1; }\necho "2 allowed commands, file ok"\n' >"$BATS_TEST_TMPDIR/gate"
    chmod +x "$BATS_TEST_TMPDIR/bin/sudoedit" "$BATS_TEST_TMPDIR/gate"
    export SUDO_GATE_BIN="$BATS_TEST_TMPDIR/gate"
}

@test "edit row opens the allow file in sudoedit with nvim and checks it" {
    edit_env
    run "$editor" </dev/null
    [ "$status" -eq 0 ]
    [[ "$(sed -n 1p "$EDIT_LOG")" == "sudoedit nvim $SUDO_GATE_ALLOW_FILE" ]]
    [[ "$(sed -n 2p "$EDIT_LOG")" == "gate check --allow $SUDO_GATE_ALLOW_FILE" ]]
    [[ "$output" == *'file ok'* ]]
}

@test "edit row keeps the window open on a bad line" {
    edit_env
    CHECK_FAIL=1 run "$editor" <<<''
    [ "$status" -eq 1 ]
    [[ "$output" == *'line 3: bad'* ]]
    [[ "$output" == *'Press Enter to close.'* ]]
}

@test "edit row stops when sudoedit fails" {
    edit_env
    SUDOEDIT_RC=1 run "$editor" <<<''
    [ "$status" -eq 1 ]
    [[ "$output" == *'sudoedit failed.'* ]]
    [[ "$(wc -l <"$EDIT_LOG")" -eq 1 ]]
}
