setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__cron_error_nudge.sh"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export CRON_STATE_DIR="$BATS_TEST_TMPDIR/jobs"
    export CRON_ERROR_NUDGE_STATE="$BATS_TEST_TMPDIR/nudged.json"
    export CRON_ERROR_GRACE_STATE="$BATS_TEST_TMPDIR/grace.json"
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
[ "${FAKE_SND_FAIL:-0}" != 1 ] || exit 1
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
    # Fake decision router: records argv and stdin, behaviour set by FAKE_ROUTER_MODE.
    ROUTER_CALLS="$BATS_TEST_TMPDIR/router_calls"
    export ROUTER_CALLS
    cat >"$BATS_TEST_TMPDIR/bin/router" <<'S'
#!/usr/bin/env bash
printf '%s\t%s\n' "$*" "$(cat)" >>"$ROUTER_CALLS"
case "${FAKE_ROUTER_MODE:-ok}" in
    fail) echo boom >&2; exit 3 ;;
    hang) sleep 30 ;;
esac
echo '{"verdict":"x"}'
S
    chmod +x "$BATS_TEST_TMPDIR/bin/router"
    export CRON_ROUTER_BIN="$BATS_TEST_TMPDIR/bin/router"
}

job() {
    printf '{"job":"%s","state":"%s","exit_code":%s,"duration_s":3,"message":"boom","log_path":"/l"}\n' \
        "$1" "$2" "${3:-1}" >"$CRON_STATE_DIR/$1.json"
}
seeded() { echo '[]' >"$CRON_ERROR_NUDGE_STATE"; echo '[]' >"$CRON_OVERRUN_NUDGE_STATE"; }

transient_job() {
    local name="$1" ts="$2" exit_code="${3:-1}"
    jq -n --arg job "$name" --argjson ts "$ts" --argjson code "$exit_code" \
        --arg log "$BATS_TEST_TMPDIR/$name.log" \
        '{job:$job, state:"error", ts:$ts, exit_code:$code, duration_s:3, message:"boom", log_path:$log}' \
        >"$CRON_STATE_DIR/$name.json"
    printf 'WARN: GitHub request failed\n' >"$BATS_TEST_TMPDIR/$name.log"
}

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

@test "historical and malformed state files do not add jq scans or hide errors" {
    seeded
    job backup error
    python3 - "$CRON_STATE_DIR" <<'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
for number in range(300):
    (root / f'retired-{number}.json').write_text(json.dumps({'state': 'no-hit'}))
(root / 'broken.json').write_text('{')
(root / 'array.json').write_text('[]')
PY
    export JQ_CALLS="$BATS_TEST_TMPDIR/jq-calls"
    export REAL_JQ
    REAL_JQ=$(command -v jq)
    cat >"$BATS_TEST_TMPDIR/bin/jq" <<'S'
#!/usr/bin/env bash
printf 'x\n' >>"$JQ_CALLS"
exec "$REAL_JQ" "$@"
S
    chmod +x "$BATS_TEST_TMPDIR/bin/jq"
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$SENT")" -eq 1 ]
    [ "$(wc -l <"$JQ_CALLS")" -lt 20 ]
    [[ "$(cat "$SENT")" == *"cron-error: backup "* ]]
}

@test "an error transition calls the router error case once with the job in the record" {
    seeded
    printf 'line1\nlast log line\n' >"$BATS_TEST_TMPDIR/job.log"
    printf '{"job":"backup","state":"error","exit_code":7,"duration_s":3,"message":"boom","log_path":"%s"}\n' \
        "$BATS_TEST_TMPDIR/job.log" >"$CRON_STATE_DIR/backup.json"
    STUB_ROUTE=intake run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$ROUTER_CALLS")" -eq 1 ]
    [[ "$(cut -f1 "$ROUTER_CALLS")" == "error cron --error "* ]]
    [[ "$(cut -f1 "$ROUTER_CALLS")" == *"--record-json -" ]]
    rec=$(cut -f2 "$ROUTER_CALLS")
    [ "$(jq -r .job <<<"$rec")" = backup ]
    [ "$(jq -r .state <<<"$rec")" = error ]
    [ "$(jq -r .exit_code <<<"$rec")" = 7 ]
    [ "$(jq -r .duration_s <<<"$rec")" = 3 ]
    [[ "$(jq -r .log_tail <<<"$rec")" == *"last log line"* ]]
}

@test "the DM is the same with the router present" {
    seeded
    job backup error
    STUB_ROUTE=intake run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(cat "$SENT")" = "intake cron-error: backup exit=1 after 3s :: boom :: log /l" ]
}

@test "a failing router does not change the DM or the exit status" {
    seeded
    job backup error
    FAKE_ROUTER_MODE=fail STUB_ROUTE=intake run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(cat "$SENT")" = "intake cron-error: backup exit=1 after 3s :: boom :: log /l" ]
    [ "$(wc -l <"$ROUTER_CALLS")" -eq 1 ]
}

@test "a hanging router is time-boxed and the DM still goes out" {
    seeded
    job backup error
    start=$SECONDS
    CRON_ROUTER_TIMEOUT_S=1 FAKE_ROUTER_MODE=hang STUB_ROUTE=intake run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ $((SECONDS - start)) -lt 10 ]
    [ "$(cat "$SENT")" = "intake cron-error: backup exit=1 after 3s :: boom :: log /l" ]
}

@test "a missing router does not change the DM" {
    seeded
    job backup error
    CRON_ROUTER_BIN="$BATS_TEST_TMPDIR/nope" STUB_ROUTE=intake run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(cat "$SENT")" = "intake cron-error: backup exit=1 after 3s :: boom :: log /l" ]
}

@test "no router call without an error transition" {
    seeded
    job backup no-hit 0
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -e "$ROUTER_CALLS" ]
}

@test "no router call on a cold start, on a repeat, or on a dry run" {
    job backup error
    run bash "$SCRIPT"
    [ ! -e "$ROUTER_CALLS" ]
    seeded
    run bash "$SCRIPT" --dry-run
    [ ! -e "$ROUTER_CALLS" ]
    seeded
    STUB_ROUTE=intake run bash "$SCRIPT"
    run bash "$SCRIPT"
    [ "$(wc -l <"$ROUTER_CALLS")" -eq 1 ]
}

@test "a transient first failure is graced without a send or router call" {
    seeded
    ts=$(date +%s)
    transient_job __github_notifications "$ts"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"graced __github_notifications exit=1 ts=$ts: single transient failure"* ]]
    [[ "$output" == *"overruns=0 graced=1"* ]]
    [ "$(jq -r '.__github_notifications' "$CRON_ERROR_GRACE_STATE")" = "$ts" ]
    [ "$(jq -c . "$CRON_ERROR_NUDGE_STATE")" = '[]' ]
    [ ! -e "$SENT" ]
    [ ! -e "$ROUTER_CALLS" ]
    [ ! -e "$ROUTED" ]
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"graced=0"* ]]
    [ ! -e "$SENT" ]
}

@test "recovery clears grace without a send" {
    seeded
    transient_job __linear_feed "$(date +%s)"
    run bash "$SCRIPT"
    job __linear_feed no-hit 0
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"grace cleared __linear_feed"* ]]
    [ "$(jq -c . "$CRON_ERROR_GRACE_STATE")" = '{}' ]
    [ ! -e "$SENT" ]
    [ ! -e "$ROUTER_CALLS" ]
}

@test "a newer consecutive failure is announced and removed from grace" {
    seeded
    ts=$(date +%s)
    transient_job __github_notifications "$ts"
    run bash "$SCRIPT"
    transient_job __github_notifications "$((ts + 1))"
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$SENT")" -eq 1 ]
    [ "$(wc -l <"$ROUTER_CALLS")" -eq 1 ]
    [ "$(jq -c . "$CRON_ERROR_GRACE_STATE")" = '{}' ]
    [ "$(jq -c . "$CRON_ERROR_NUDGE_STATE")" = '["__github_notifications"]' ]
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(wc -l <"$SENT")" -eq 1 ]
}

@test "a stale failure with the same timestamp is announced" {
    seeded
    ts=$(($(date +%s) - 100))
    transient_job __github_notifications "$ts"
    CRON_ERROR_GRACE_MAX_S=200 run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    CRON_ERROR_GRACE_MAX_S=10 run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$SENT")" -eq 1 ]
    [ "$(jq -c . "$CRON_ERROR_GRACE_STATE")" = '{}' ]
}

@test "a job outside the allowlist is announced immediately" {
    seeded
    transient_job backup "$(date +%s)"
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$SENT")" -eq 1 ]
    [ ! -e "$CRON_ERROR_GRACE_STATE" ]
}

@test "an ERROR line prevents grace" {
    seeded
    transient_job __linear_feed "$(date +%s)"
    printf 'ERROR: another failure\n' >>"$BATS_TEST_TMPDIR/__linear_feed.log"
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$SENT")" -eq 1 ]
}

@test "exit 2 prevents grace" {
    seeded
    transient_job __linear_feed "$(date +%s)" 2
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$SENT")" -eq 1 ]
}

@test "a matching error on cold start is seeded without grace" {
    transient_job __github_notifications "$(date +%s)"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -e "$SENT" ]
    [ ! -e "$CRON_ERROR_GRACE_STATE" ]
    [ "$(jq -c . "$CRON_ERROR_NUDGE_STATE")" = '["__github_notifications"]' ]
}

@test "dry run reports grace without writing it" {
    seeded
    transient_job __github_notifications "$(date +%s)"
    run bash "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would grace __github_notifications"* ]]
    [ ! -e "$CRON_ERROR_GRACE_STATE" ]
    [ ! -e "$SENT" ]
    [ "$(jq -c . "$CRON_ERROR_NUDGE_STATE")" = '[]' ]
}

@test "dry run of a repeated failure preserves grace for live delivery" {
    seeded
    ts=$(date +%s)
    transient_job __github_notifications "$ts"
    run bash "$SCRIPT"
    transient_job __github_notifications "$((ts + 1))"
    run bash "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would send to"* ]]
    [ "$(jq -r '.__github_notifications' "$CRON_ERROR_GRACE_STATE")" = "$ts" ]
    [ "$(jq -c . "$CRON_ERROR_NUDGE_STATE")" = '[]' ]
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$SENT")" -eq 1 ]
}

@test "grace checks only the last 20 log lines and honors custom settings" {
    seeded
    transient_job custom "$(date +%s)"
    { printf 'ERROR: old failure\n'; for _ in {1..20}; do printf 'temporary custom failure\n'; done; } >"$BATS_TEST_TMPDIR/custom.log"
    CRON_ERROR_GRACE_JOBS=custom CRON_ERROR_GRACE_RE='temporary custom failure' run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(jq 'has("custom")' "$CRON_ERROR_GRACE_STATE")" = true ]
    [ ! -e "$SENT" ]
}

@test "a different error without a transient signature is announced" {
    seeded
    transient_job __github_notifications "$(date +%s)"
    printf 'connection refused\n' >"$BATS_TEST_TMPDIR/__github_notifications.log"
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$SENT")" -eq 1 ]
}

@test "a failed delivery after grace is retried on the next tick" {
    seeded
    ts=$(date +%s)
    transient_job __github_notifications "$ts"
    run bash "$SCRIPT"
    transient_job __github_notifications "$((ts + 1))"
    FAKE_SND_FAIL=1 run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [ "$(jq -r '.__github_notifications' "$CRON_ERROR_GRACE_STATE")" = "$ts" ]
    [ "$(jq -c . "$CRON_ERROR_NUDGE_STATE")" = '[]' ]
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [ "$(wc -l <"$SENT")" -eq 1 ]
    [ "$(jq -c . "$CRON_ERROR_GRACE_STATE")" = '{}' ]
}

@test "dry run recovery leaves existing grace state unchanged" {
    seeded
    transient_job __linear_feed "$(date +%s)"
    run bash "$SCRIPT"
    before=$(cat "$CRON_ERROR_GRACE_STATE")
    job __linear_feed no-hit 0
    run bash "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [ "$(cat "$CRON_ERROR_GRACE_STATE")" = "$before" ]
    run bash "$SCRIPT"
    [ "$(jq -c . "$CRON_ERROR_GRACE_STATE")" = '{}' ]
}
