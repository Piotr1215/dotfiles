setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__cron_error_nudge.sh"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export CRON_STATE_DIR="$BATS_TEST_TMPDIR/jobs"
    export CRON_ERROR_NUDGE_STATE="$BATS_TEST_TMPDIR/nudged.json"
    export CRON_ERROR_NUDGE_LOCK="$BATS_TEST_TMPDIR/lock"
    export CRON_OVERRUN_NUDGE_STATE="$BATS_TEST_TMPDIR/overrun.json"
    export SND_NODE_BIN=snd.js
    mkdir -p "$CRON_STATE_DIR" "$BATS_TEST_TMPDIR/bin"
    SENT="$BATS_TEST_TMPDIR/sent"
    ROUTED="$BATS_TEST_TMPDIR/routed"
    export SENT ROUTED
    # node: records "<target> <line>" for each snd.js call.
    cat >"$BATS_TEST_TMPDIR/bin/node" <<'S'
#!/usr/bin/env bash
printf '%s %s\n' "$3" "$4" >>"$SENT"
S
    # __intake_route.sh: counts its calls, answers STUB_ROUTE.
    cat >"$BATS_TEST_TMPDIR/bin/route" <<'S'
#!/usr/bin/env bash
echo x >>"$ROUTED"
echo "${STUB_ROUTE:-triage}"
S
    chmod +x "$BATS_TEST_TMPDIR/bin/node" "$BATS_TEST_TMPDIR/bin/route"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export INTAKE_ROUTE_BIN="$BATS_TEST_TMPDIR/bin/route"
    unset CRON_ERROR_NUDGE_TO
}

job() {
    printf '{"job":"%s","state":"%s","exit_code":%s,"duration_s":3,"message":"boom","log_path":"/l"}\n' \
        "$1" "$2" "${3:-1}" >"$CRON_STATE_DIR/$1.json"
}
seeded() { echo '[]' >"$CRON_ERROR_NUDGE_STATE"; echo '[]' >"$CRON_OVERRUN_NUDGE_STATE"; }

teardown() { [ -z "${WRAPPER_PID:-}" ] || kill "$WRAPPER_PID" 2>/dev/null || true; }

# A live process whose command line reads like __cron_run.sh's for job $1.
wrapper() {
    printf '#!/usr/bin/env bash\nsleep 30\n' >"$BATS_TEST_TMPDIR/__cron_run.sh"
    chmod +x "$BATS_TEST_TMPDIR/__cron_run.sh"
    "$BATS_TEST_TMPDIR/__cron_run.sh" "$1" -- x &
    WRAPPER_PID=$!
}

# running <job> <started seconds ago> <previous duration> [pid]
running() {
    printf '{"job":"%s","state":"running","ts":%s,"pid":%s,"log_path":"/l","prev_duration_s":%s}\n' \
        "$1" "$(($(date +%s) - $2))" "${4:-$WRAPPER_PID}" "$3" >"$CRON_STATE_DIR/$1.json"
}

@test "a newly broken job goes to intake while Kendra holds the stream" {
    seeded
    job backup error
    STUB_ROUTE=intake run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(cat "$SENT")" = "intake cron-error: backup exit=1 after 3s :: boom :: log /l" ]
}

@test "it goes to triage when the route says so" {
    seeded
    job backup error
    STUB_ROUTE=triage run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(cut -d' ' -f1 "$SENT")" = "triage" ]
}

@test "CRON_ERROR_NUDGE_TO wins and the route is not asked" {
    seeded
    job backup error
    CRON_ERROR_NUDGE_TO=worker STUB_ROUTE=intake run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(cut -d' ' -f1 "$SENT")" = "worker" ]
    [ ! -e "$ROUTED" ]
}

@test "nothing new sends nothing and never asks the route" {
    seeded
    job backup no-hit 0
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -e "$SENT" ]
    [ ! -e "$ROUTED" ]
}

@test "a job still in error is announced once" {
    seeded
    job backup error
    STUB_ROUTE=intake run bash "$SCRIPT"
    STUB_ROUTE=intake run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(wc -l <"$SENT")" -eq 1 ]
}

@test "a cold start seeds silently" {
    job backup error
    STUB_ROUTE=intake run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -e "$SENT" ]
    [ "$(jq -c . "$CRON_ERROR_NUDGE_STATE")" = '["backup"]' ]
}

@test "a live run past its limit is announced once" {
    seeded
    wrapper slow
    running slow 3700 100
    STUB_ROUTE=intake run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$(cat "$SENT")" == "intake cron-overrun: slow running 61m (previous run 100s) pid $WRAPPER_PID :: log /l" ]]
    STUB_ROUTE=intake run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(wc -l <"$SENT")" -eq 1 ]
}

@test "a slow job within four times its previous duration is not an overrun" {
    seeded
    wrapper slow
    running slow 3700 1000
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -e "$SENT" ]
}

@test "a running marker whose process is gone is not an overrun" {
    seeded
    running slow 3700 100 999999
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -e "$SENT" ]
}

@test "the next run of the same job can overrun again" {
    seeded
    wrapper slow
    running slow 3700 100
    run bash "$SCRIPT"
    running slow 3800 100
    run bash "$SCRIPT"
    [ "$(wc -l <"$SENT")" -eq 2 ]
}

@test "a cold start seeds overruns silently" {
    echo '[]' >"$CRON_ERROR_NUDGE_STATE"
    wrapper slow
    running slow 3700 100
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -e "$SENT" ]
    [ "$(jq length "$CRON_OVERRUN_NUDGE_STATE")" -eq 1 ]
}
