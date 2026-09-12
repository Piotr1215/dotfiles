#!/usr/bin/env bats
# Tests for scripts/__lib_cron_view.sh: the crontab parser and staleness
# budget shared by the argos cron-status widget and __cron_status_dump.sh.

setup() {
    LIB="$BATS_TEST_DIRNAME/../../scripts/__lib_cron_view.sh"
    source "$LIB"
    FIXTURE="$BATS_TEST_TMPDIR/crontab"
    export CRON_REGISTRY_FILE="$FIXTURE"
    RUN="/home/x/scripts/__cron_run.sh"
    EVERY="/home/x/scripts/__cron_every.sh"
}

@test "registry: one row per job, wrapped name is authoritative" {
    cat >"$FIXTURE" <<EOF
# comment
DISPLAY=:1

*/5 * * * * $RUN __reaper -- /home/x/scripts/__reaper.sh
0 7 * * * $RUN __brief -- /home/x/scripts/__brief.sh
EOF
    run cron_registry
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = $'*/5 * * * *\t__reaper\t'"$RUN __reaper -- /home/x/scripts/__reaper.sh "$'\t' ]
    [[ "${lines[1]}" == $'0 7 * * *\t__brief\t'* ]]
}

@test "registry: the comment line touching a job is its purpose" {
    cat >"$FIXTURE" <<EOF
# Boot window notes, two lines of them.
# Backup dead-man's switch.
11 10 * * * $RUN __backup_watchdog -- /home/x/scripts/__backup_watchdog.sh

# DISABLED: 0 10 * * * /home/x/old.sh

0 20 * * * $RUN __backup -- /nonexistent/__backup.sh
EOF
    run cron_registry
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[0]}" == *$'\tBackup dead-man'"'"'s switch.' ]]
    # A blank line breaks the block: the DISABLED note is nobody's purpose,
    # and a script that cannot be read yields an empty purpose, not a crash.
    [[ "${lines[1]}" == *$'\t__backup\t'*$'\t' ]]
}

@test "registry: bare line is named after its script, @reboot gets a suffix" {
    cat >"$FIXTURE" <<EOF
*/15 * * * * /home/x/scripts/__close_done.sh >/dev/null 2>&1
@reboot sleep 90 && /home/x/scripts/__reminder.sh sync
EOF
    run cron_registry
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[0]}" == $'*/15 * * * *\t__close_done\t'* ]]
    [[ "${lines[1]}" == $'@reboot\t__reminder-reboot\t'* ]]
}

@test "registry: the managed remind block is not listed" {
    cat >"$FIXTURE" <<EOF
0 7 * * * $RUN __brief -- /home/x/scripts/__brief.sh
# BEGIN remind (managed by __reminder.sh sync, edits here are overwritten)
@reboot sleep 90 && /home/x/scripts/__reminder.sh sync
*/15 * * * * $EVERY remind-abc 604800 -- $RUN remind-abc -- /home/x/scripts/__reminder.sh fire abc
# END remind
0 20 * * * $RUN __backup -- /home/x/scripts/__backup.sh
EOF
    run cron_registry
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[0]}" == *$'\t__brief\t'* ]]
    [[ "${lines[1]}" == *$'\t__backup\t'* ]]
}

@test "registry: cron_every guard does not hide the wrapped job name" {
    cat >"$FIXTURE" <<EOF
50 * * * * $EVERY r2r-full 604800 -- $RUN __r2r_sync-full -- /home/x/scripts/__r2r_sync.sh --full
EOF
    run cron_registry
    [[ "${lines[0]}" == $'50 * * * *\t__r2r_sync-full\t'* ]]
}

@test "budget: twice the schedule's own interval" {
    [ "$(cron_expected_interval '*/5 * * * *')" -eq 600 ]
    [ "$(cron_expected_interval '10,40 * * * *')" -eq 7200 ]
    [ "$(cron_expected_interval '20 * * * *')" -eq 7200 ]
    [ "$(cron_expected_interval '15 */2 * * *')" -eq 14400 ]
    [ "$(cron_expected_interval '0 7 * * *')" -eq 172800 ]
    [ "$(cron_expected_interval '5,35 7-11 * * *')" -eq 172800 ]
    [ "$(cron_expected_interval '0 13 * * SAT')" -eq 1209600 ]
    [ "$(cron_expected_interval '@reboot')" -eq 2592000 ]
}

@test "budget: a cron_every guard sets the budget from its interval, not the tick" {
    local cmd="$EVERY r2r-full 604800 -- $RUN __r2r_sync-full -- /home/x/s.sh"
    [ "$(cron_expected_interval '50 * * * *' "$cmd")" -eq 1209600 ]
}

@test "overdue: a daily job last run 20 days ago is overdue, one run 1h ago is not" {
    local now; now=$(date +%s)
    cron_overdue "$(( now - 20 * 86400 ))" '0 7 * * *'
    ! cron_overdue "$(( now - 3600 ))" '0 7 * * *'
}

@test "overdue: a weekly cron_every job run 6 days ago is on schedule" {
    local now; now=$(date +%s)
    local cmd="$EVERY r2r-full 604800 -- $RUN __r2r_sync-full -- /home/x/s.sh"
    ! cron_overdue "$(( now - 6 * 86400 ))" '50 * * * *' "$cmd"
    cron_overdue "$(( now - 15 * 86400 ))" '50 * * * *' "$cmd"
}

@test "overdue: no timestamp is never overdue" {
    ! cron_overdue "" '0 7 * * *'
}

@test "spent: a tripped verificator's message is recognised" {
    cron_spent "[2026-09-11T18:27:01+0200] already tripped for slug (2026-09-03 STALE); nothing to do"
    ! cron_spent "SUMMARY: reaped=0 blocked=0"
}

@test "words: schedules read as a person would say them" {
    [ "$(cron_human_schedule '*/5 * * * *')" = "every 5m" ]
    [ "$(cron_human_schedule '3-59/5 * * * *')" = "every 5m" ]
    [ "$(cron_human_schedule '4,19,34,49 * * * *')" = "every 15m" ]
    [ "$(cron_human_schedule '10,40 * * * *')" = "hourly :10,:40" ]
    [ "$(cron_human_schedule '50 * * * *')" = "hourly :50" ]
    [ "$(cron_human_schedule '15 */2 * * *')" = "every 2h at :15" ]
    [ "$(cron_human_schedule '0 20 * * *')" = "daily 20:00" ]
    [ "$(cron_human_schedule '5,35 7-11 * * *')" = "daily 07:05 to 11:35" ]
    [ "$(cron_human_schedule '21 10 * * 1')" = "Mon 10:21" ]
    [ "$(cron_human_schedule '0 13 * * SAT')" = "Sat 13:00" ]
    [ "$(cron_human_schedule '@reboot')" = "at boot" ]
}

@test "words: a cron_every guard names the real cadence, unknown shapes stay raw" {
    [ "$(cron_human_schedule '50 * * * *' "$EVERY x 604800 -- $RUN j -- /s.sh")" = "weekly" ]
    [ "$(cron_human_schedule '0 0 1 * *')" = "0 0 1 * *" ]
}
