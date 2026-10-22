setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__cron_error_nudge.sh"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export CRON_STATE_DIR="$BATS_TEST_TMPDIR/jobs"
    export CRON_ERROR_NUDGE_STATE="$BATS_TEST_TMPDIR/nudged.json"
    export CRON_ERROR_NUDGE_LOCK="$BATS_TEST_TMPDIR/lock"
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
seeded() { echo '[]' >"$CRON_ERROR_NUDGE_STATE"; }

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
