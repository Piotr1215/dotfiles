#!/usr/bin/env bats
setup() {
    bats_require_minimum_version 1.5.0
    root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export HOME="$BATS_TEST_TMPDIR/home" SUDO_GATE_PENDING_DIR="$BATS_TEST_TMPDIR/pending"
    export SUDO_GATE_TEST_MODE=1 SUDO_GATE_TEST_COMM=sleep
    export SECRETS_DIR="$HOME/.secrets" PASSWORD_STORE_DIR="$HOME/.password-store"
    export LOG="$BATS_TEST_TMPDIR/log"
    mkdir -p "$HOME/dev" "$SECRETS_DIR" "$PASSWORD_STORE_DIR/work" "$SUDO_GATE_PENDING_DIR" "$BATS_TEST_TMPDIR/bin" "$HOME/.ssh"
    ln -s "$root" "$HOME/dev/dotfiles"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    # shellcheck disable=SC2016
    printf '#!/bin/sh\necho age >>"$LOG"\n' >"$BATS_TEST_TMPDIR/bin/age"
    # shellcheck disable=SC2016
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"$LOG"\n' >"$BATS_TEST_TMPDIR/bin/notify-send"
    chmod +x "$BATS_TEST_TMPDIR/bin/age" "$BATS_TEST_TMPDIR/bin/notify-send"
    printf 'cipher' >"$SECRETS_DIR/TEST.age"
    sleep 300 & sleeper=$!
    jq -n --argjson pid "$sleeper" --argjson ts "$(date +%s)" '{sudo_pid:$pid,ts:$ts,command:"sudo id",detection:"agent",agent:"worker"}' >"$SUDO_GATE_PENDING_DIR/$sleeper.json"
}
teardown() { kill "$sleeper" 2>/dev/null || :; wait "$sleeper" 2>/dev/null || :; }
# The refusal is said on stderr only: no desktop notification about a root
# request (Piotr, 28 Nov: "I don't want to see notifications", "but argos").
no_root_popup() {
    if [ -e "$LOG" ] && grep -Eqi 'root request|Cannot verify' "$LOG"; then return 1; fi
}
assert_blocked() {
    [ "$status" -ne 0 ]
    [[ "$output" == *'A root request is waiting for the YubiKey: touch or refuse it first (top bar)'* ]]
    run ! grep -q '^age$' "$LOG"
    no_root_popup
}
@test "sec blocks before age" {
    run zsh -c 'source "$1/.config/age/secret.zsh"; sec TEST' -- "$root"
    assert_blocked
}
@test "secret object read and demote block before age" {
    run bash -c 'source "$1/scripts/__lib_secret_object.sh"; secret_read TEST' -- "$root"
    assert_blocked
    run bash -c 'source "$1/scripts/__lib_secret_object.sh"; secret_demote TEST work' -- "$root"
    assert_blocked
    [ ! -e "$PASSWORD_STORE_DIR/work/TEST.gpg" ]
}
@test "picker blocks before age" {
    # shellcheck disable=SC2016
    printf '#!/bin/sh\nprintf "0\\n"\nexit 0\n' >"$BATS_TEST_TMPDIR/bin/rofi"
    printf '#!/bin/sh\ncat >/dev/null\n' >"$BATS_TEST_TMPDIR/bin/xsel"
    chmod +x "$BATS_TEST_TMPDIR/bin/rofi" "$BATS_TEST_TMPDIR/bin/xsel"
    run "$root/scripts/__secret_picker.sh"
    assert_blocked
}
@test "ghshare blocks age decrypt" {
    printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' >"$HOME/.ssh/id_test"
    run bash -c 'printf "%s\n" "-----BEGIN AGE ENCRYPTED FILE-----" "data" "-----END AGE ENCRYPTED FILE-----" | "$1/scripts/__ghshare.sh" -d' -- "$root"
    assert_blocked
}

@test "locked runner preserves command status without a pending request" {
    export SUDO_GATE_LOCK_FILE="$BATS_TEST_TMPDIR/touch-lock"
    : >"$SUDO_GATE_LOCK_FILE"
    rm "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    run "$root/scripts/__sudo_gate_busy.sh" --run bash -c 'exit 37'
    [ "$status" -eq 37 ]
    [ -f "$SUDO_GATE_LOCK_FILE" ]
    run flock -n "$SUDO_GATE_LOCK_FILE" true
    [ "$status" -eq 0 ]
}

@test "locked runner waits for publication then refuses a pending request" {
    export SUDO_GATE_LOCK_FILE="$BATS_TEST_TMPDIR/touch-lock"
    : >"$SUDO_GATE_LOCK_FILE"
    mv "$SUDO_GATE_PENDING_DIR/$sleeper.json" "$BATS_TEST_TMPDIR/queued"
    exec 9<"$SUDO_GATE_LOCK_FILE"
    flock -x 9
    "$root/scripts/__sudo_gate_busy.sh" --run touch "$BATS_TEST_TMPDIR/ran" >"$BATS_TEST_TMPDIR/output" 2>&1 &
    runner=$!
    sleep 0.1
    kill -0 "$runner"
    [ ! -e "$BATS_TEST_TMPDIR/ran" ]
    mv "$BATS_TEST_TMPDIR/queued" "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    flock -u 9
    result=0
    wait "$runner" || result=$?
    [ "$result" -eq 75 ]
    [ ! -e "$BATS_TEST_TMPDIR/ran" ]
    grep -Fxq 'A root request is waiting for the YubiKey: touch or refuse it first (top bar)' "$BATS_TEST_TMPDIR/output"
    no_root_popup
}

@test "locked runner holds lock until the decrypt exits" {
    export SUDO_GATE_LOCK_FILE="$BATS_TEST_TMPDIR/touch-lock" RUN_MARK="$BATS_TEST_TMPDIR/started" FINISH_MARK="$BATS_TEST_TMPDIR/finish"
    : >"$SUDO_GATE_LOCK_FILE"
    rm "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    "$root/scripts/__sudo_gate_busy.sh" --run bash -c 'touch "$RUN_MARK"; while [ ! -e "$FINISH_MARK" ]; do sleep 0.02; done' &
    runner=$!
    for _ in {1..100}; do [ -e "$RUN_MARK" ] && break; sleep 0.01; done
    [ -e "$RUN_MARK" ]
    run flock -n "$SUDO_GATE_LOCK_FILE" true
    [ "$status" -ne 0 ]
    touch "$FINISH_MARK"
    wait "$runner"
    run flock -n "$SUDO_GATE_LOCK_FILE" true
    [ "$status" -eq 0 ]
}

@test "ghshare preserves blocked status on forced, file, and piped decrypts" {
    printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' >"$HOME/.ssh/id_test"
    printf '%s\n' '-----BEGIN AGE ENCRYPTED FILE-----' data '-----END AGE ENCRYPTED FILE-----' >"$BATS_TEST_TMPDIR/block.age"
    for mode in forced file piped; do
        case "$mode" in
        forced) run "$root/scripts/__ghshare.sh" -d "$BATS_TEST_TMPDIR/block.age" ;;
        file) run "$root/scripts/__ghshare.sh" "$BATS_TEST_TMPDIR/block.age" ;;
        piped) run bash -c '"$1/scripts/__ghshare.sh" <"$2"' -- "$root" "$BATS_TEST_TMPDIR/block.age" ;;
        esac
        [ "$status" -eq 75 ]
        [[ "$output" != *"keys can open"* ]]
        [[ "$output" != *"your keys"* ]]
        [[ "$output" == *'A root request is waiting for the YubiKey: touch or refuse it first (top bar)'* ]]
    done
    no_root_popup
    run ! grep -q '^age$' "$LOG"
}

@test "ghshare clipboard block stops before recipient prompt when root is pending" {
    printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' >"$HOME/.ssh/id_test"
    printf '%s\n' '-----BEGIN AGE ENCRYPTED FILE-----' data '-----END AGE ENCRYPTED FILE-----' >"$BATS_TEST_TMPDIR/block.age"
    export BLOCK_FILE="$BATS_TEST_TMPDIR/block.age" GHSHARE_GHUSER_CMD="$BATS_TEST_TMPDIR/bin/ghuser"
    unset GHSHARE_NO_CLIPBOARD
    # shellcheck disable=SC2016
    printf '#!/bin/sh\ncat "$BLOCK_FILE"\n' >"$BATS_TEST_TMPDIR/bin/xsel"
    # shellcheck disable=SC2016
    printf '#!/bin/sh\necho prompted >>"$LOG"\n' >"$GHSHARE_GHUSER_CMD"
    printf '#!/bin/sh\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/fzf"
    chmod +x "$BATS_TEST_TMPDIR/bin/xsel" "$GHSHARE_GHUSER_CMD" "$BATS_TEST_TMPDIR/bin/fzf"
    run timeout 3 script -q -e -c "$root/scripts/__ghshare.sh" /dev/null </dev/null
    [ "$status" -eq 75 ]
    [[ "$output" != *"keys can open"* ]]
    [[ "$output" == *'A root request is waiting for the YubiKey: touch or refuse it first (top bar)'* ]]
    run ! grep -q '^prompted$' "$LOG"
    no_root_popup
}

@test "sec shows no touch cue while gate holds lock and publishes a request" {
    export SUDO_GATE_LOCK_FILE="$BATS_TEST_TMPDIR/touch-lock"
    : >"$SUDO_GATE_LOCK_FILE"
    mv "$SUDO_GATE_PENDING_DIR/$sleeper.json" "$BATS_TEST_TMPDIR/queued"
    exec 9<"$SUDO_GATE_LOCK_FILE"
    flock -x 9
    export LOCK_ATTEMPT="$BATS_TEST_TMPDIR/lock-attempt"
    cat >"$BATS_TEST_TMPDIR/bin/flock" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == -x ]] && touch "$LOCK_ATTEMPT"
exec /usr/bin/flock "$@"
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/flock"
    zsh -c 'source "$1/.config/age/secret.zsh"; sec TEST' -- "$root" >"$BATS_TEST_TMPDIR/sec.out" 2>&1 &
    runner=$!
    for _ in {1..100}; do [ -e "$LOCK_ATTEMPT" ] && break; sleep 0.01; done
    [ -e "$LOCK_ATTEMPT" ]
    kill -0 "$runner"
    ! grep -q 'TOUCH\|Touch the key' "$BATS_TEST_TMPDIR/sec.out" || return 1
    [ ! -e "$LOG" ] || ! grep -q 'Touch the key' "$LOG" || return 1
    mv "$BATS_TEST_TMPDIR/queued" "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    flock -u 9
    result=0
    wait "$runner" || result=$?
    [ "$result" -eq 75 ]
    grep -Fq 'A root request is waiting for the YubiKey: touch or refuse it first (top bar)' "$BATS_TEST_TMPDIR/sec.out"
    no_root_popup
    run ! grep -q '^age$' "$LOG"
}

@test "picker shows no touch cue while gate holds lock and publishes a request" {
    export SUDO_GATE_LOCK_FILE="$BATS_TEST_TMPDIR/touch-lock" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
    mkdir -p "$XDG_RUNTIME_DIR"
    : >"$SUDO_GATE_LOCK_FILE"
    mv "$SUDO_GATE_PENDING_DIR/$sleeper.json" "$BATS_TEST_TMPDIR/queued"
    printf '#!/bin/sh\nprintf "0\\n"\nexit 0\n' >"$BATS_TEST_TMPDIR/bin/rofi"
    printf '#!/bin/sh\ncat >/dev/null\n' >"$BATS_TEST_TMPDIR/bin/xsel"
    chmod +x "$BATS_TEST_TMPDIR/bin/rofi" "$BATS_TEST_TMPDIR/bin/xsel"
    exec 9<"$SUDO_GATE_LOCK_FILE"
    flock -x 9
    export LOCK_ATTEMPT="$BATS_TEST_TMPDIR/lock-attempt"
    cat >"$BATS_TEST_TMPDIR/bin/flock" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == -x ]] && touch "$LOCK_ATTEMPT"
exec /usr/bin/flock "$@"
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/flock"
    "$root/scripts/__secret_picker.sh" >"$BATS_TEST_TMPDIR/picker.out" 2>&1 &
    runner=$!
    for _ in {1..100}; do [ -e "$LOCK_ATTEMPT" ] && break; sleep 0.01; done
    [ -e "$LOCK_ATTEMPT" ]
    kill -0 "$runner"
    [ ! -e "$XDG_RUNTIME_DIR/secret-picker-touch" ]
    mv "$BATS_TEST_TMPDIR/queued" "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    flock -u 9
    result=0
    wait "$runner" || result=$?
    [ "$result" -ne 0 ]
    [ ! -e "$XDG_RUNTIME_DIR/secret-picker-touch" ]
    # The picker has no terminal and drops age's stderr: the red label is the
    # only cue, so it exits without any popup.
    no_root_popup
    ! grep -Eqi 'no tap|touch the key|Touch the YubiKey' "$LOG"
}

@test "malformed pending state blocks unlock even without the lock" {
    rm "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    printf '{bad' >"$SUDO_GATE_PENDING_DIR/bad.json"
    export SUDO_GATE_LOCK_FILE="$BATS_TEST_TMPDIR/missing-lock"
    run "$root/scripts/__sudo_gate_busy.sh" --run age
    [ "$status" -eq 75 ]
    [[ "$output" == *'Cannot verify root requests; unlock blocked'* ]]
    no_root_popup
    run ! grep -q '^age$' "$LOG"
}

@test "unreadable pending record returns unknown and blocks unlock" {
    rm "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    mkdir "$SUDO_GATE_PENDING_DIR/123.json"
    export SUDO_GATE_LOCK_FILE="$BATS_TEST_TMPDIR/touch-lock"
    : >"$SUDO_GATE_LOCK_FILE"
    run "$root/scripts/__sudo_gate_busy.sh"
    [ "$status" -eq 2 ]
    run "$root/scripts/__sudo_gate_busy.sh" --run age
    [ "$status" -eq 75 ]
    ! grep -q '^age$' "$LOG"
}

@test "missing lock with pending files blocks even if request is stale" {
    rm "$SUDO_GATE_PENDING_DIR/$sleeper.json"
    jq -n --argjson pid "$sleeper" --argjson ts "$(( $(date +%s) - 300 ))" '{sudo_pid:$pid,ts:$ts,command:"sudo id",detection:"agent",agent:"worker"}' >"$SUDO_GATE_PENDING_DIR/$sleeper.json"
    export SUDO_GATE_LOCK_FILE="$BATS_TEST_TMPDIR/missing-lock"
    run "$root/scripts/__sudo_gate_busy.sh" --run age
    [ "$status" -eq 75 ]
    ! grep -q '^age$' "$LOG"
}

@test "missing lock and pending directory preserves normal unlock" {
    export SUDO_GATE_LOCK_FILE="$BATS_TEST_TMPDIR/missing-lock" SUDO_GATE_PENDING_DIR="$BATS_TEST_TMPDIR/no-gate"
    run "$root/scripts/__sudo_gate_busy.sh" --run bash -c 'exit 37'
    [ "$status" -eq 37 ]
}
