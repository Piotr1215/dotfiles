#!/usr/bin/env bats

# Test suite for __pr_movement_nudge.sh — the classification and dedup logic that
# decides whether a PR movement is worth a DM to triage (Gordon).
#
# Run from the repo root:  bats tests/bats/pr_movement_nudge_test.bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    # Source only the helpers, not the flock/main tail that would run a real cycle.
    sed '/^# --- main ---$/,$d' scripts/__pr_movement_nudge.sh > "${TEST_DIR}/fns.sh"
    # shellcheck source=/dev/null
    source "${TEST_DIR}/fns.sh"
}

teardown() {
    rm -rf "${TEST_DIR}"
}

# checks_for ROLLUP_JSON -> the .checks verdict compute_sig derives from it
checks_for() {
    compute_sig "{\"statusCheckRollup\":$1}" | jq -r '.checks'
}

# --- checks classification ---------------------------------------------------

@test "compute_sig: a CANCELLED re-run beside a same-named SUCCESS is not red" {
    # loft-sh/vcluster#4084: a concurrency group cancelled the in-flight run when
    # a new commit landed, so the rollup kept the aborted row next to the re-run
    # that succeeded. The PR was green and MERGEABLE, yet the watcher DM'd ci-red
    # every hour because CANCELLED was in the failure set. (regression for that)
    run checks_for '[{"name":"build","conclusion":"CANCELLED","status":"COMPLETED"},
                     {"name":"build","conclusion":"SUCCESS","status":"COMPLETED"}]'
    [ "$output" = "SUCCESS" ]
}

@test "compute_sig: CANCELLED alone is not red" {
    run checks_for '[{"name":"e2e","conclusion":"CANCELLED","status":"COMPLETED"}]'
    [ "$output" = "SUCCESS" ]
}

@test "compute_sig: a real FAILURE is still red" {
    run checks_for '[{"name":"e2e","conclusion":"FAILURE","status":"COMPLETED"}]'
    [ "$output" = "FAILURE" ]
}

@test "compute_sig: TIMED_OUT and STARTUP_FAILURE are still red" {
    run checks_for '[{"name":"e2e","conclusion":"TIMED_OUT","status":"COMPLETED"}]'
    [ "$output" = "FAILURE" ]
    run checks_for '[{"name":"e2e","conclusion":"STARTUP_FAILURE","status":"COMPLETED"}]'
    [ "$output" = "FAILURE" ]
}

@test "compute_sig: a legacy StatusContext state=FAILURE is still red" {
    run checks_for '[{"context":"legacy/ci","state":"FAILURE"}]'
    [ "$output" = "FAILURE" ]
}

@test "compute_sig: a real FAILURE still wins alongside a CANCELLED row" {
    run checks_for '[{"name":"a","conclusion":"CANCELLED","status":"COMPLETED"},
                     {"name":"b","conclusion":"FAILURE","status":"COMPLETED"}]'
    [ "$output" = "FAILURE" ]
}

@test "compute_sig: SKIPPED and NEUTRAL are green" {
    run checks_for '[{"name":"a","conclusion":"SKIPPED","status":"COMPLETED"},
                     {"name":"b","conclusion":"NEUTRAL","status":"COMPLETED"}]'
    [ "$output" = "SUCCESS" ]
}

@test "compute_sig: an in-flight check is PENDING, not red" {
    run checks_for '[{"name":"a","status":"IN_PROGRESS"}]'
    [ "$output" = "PENDING" ]
}

@test "compute_sig: an empty rollup is NONE" {
    run checks_for '[]'
    [ "$output" = "NONE" ]
}

# --- sticky dedup ------------------------------------------------------------

@test "sticky_set: reports every true sticky state in canonical order" {
    run sticky_set '{"changesRequested":true,"checks":"FAILURE","mergeable":"CONFLICTING"}'
    [ "$output" = '["changes-requested","ci-red","merge-conflict"]' ]
}

@test "sticky_set: a clean PR has no sticky reasons" {
    run sticky_set '{"changesRequested":false,"checks":"SUCCESS","mergeable":"MERGEABLE"}'
    [ "$output" = '[]' ]
}

@test "sticky_new: an already-notified reason stays silent" {
    # The dedup itself: vcluster-pro#1510 sat CHANGES_REQUESTED + CONFLICTING all
    # morning and re-DM'd on two desynced hourly timers.
    run sticky_new '["changes-requested","merge-conflict"]' '["changes-requested","merge-conflict"]'
    [ -z "$output" ]
}

@test "sticky_new: only the newly-entered reason fires" {
    # Alert-on-new-state must survive the dedup: merge-conflict is new, and
    # changes-requested (already sent) must not ride along again.
    run sticky_new '["changes-requested","merge-conflict"]' '["changes-requested"]'
    [ "$output" = "merge-conflict" ]
}

@test "sticky_new: every reason fires when nothing has been notified yet" {
    run sticky_new '["ci-red","merge-conflict"]' '[]'
    [ "${lines[0]}" = "ci-red" ]
    [ "${lines[1]}" = "merge-conflict" ]
}

@test "sticky_new: a reason that cleared and returned fires again" {
    run sticky_new '["ci-red"]' '[]'
    [ "$output" = "ci-red" ]
}

# --- bare ci-red noise suppression (unchanged behavior, guarded) --------------

@test "ci_red_is_noise: CI and dependency PR titles suppress a bare ci-red" {
    run ci_red_is_noise "ci(release): migrate sync_linear to the shared action"
    [ "$status" -eq 0 ]
    run ci_red_is_noise "chore(deps): bump golang.org/x/net to 0.38.0"
    [ "$status" -eq 0 ]
}

@test "ci_red_is_noise: a normal code PR does not suppress ci-red" {
    run ci_red_is_noise "fix(syncer): stop dropping events on resync"
    [ "$status" -ne 0 ]
}
