#!/usr/bin/env bats
# Tests for scripts/__cron_edit.sh: open the crontab on a job's line, install
# only a changed buffer, keep a rejected edit for retry.

setup() {
    EDIT="$BATS_TEST_DIRNAME/../../scripts/__cron_edit.sh"
    WORK="$BATS_TEST_TMPDIR"
    export HOME="$WORK/home"
    mkdir -p "$HOME/.local/state/cron-jobs" "$WORK/bin"
    SPOOL="$WORK/spool"
    cat >"$SPOOL" <<EOF
# header
0 20 * * * /x/__cron_run.sh __backup -- /x/__backup.sh

# Backup dead-man's switch.
11 10 * * * /x/__cron_run.sh __backup_watchdog -- /x/__backup_watchdog.sh
EOF
    # crontab stand-in: -l prints the spool, <file> installs it unless it
    # carries GARBAGE, in which case it refuses like the real one.
    cat >"$WORK/bin/crontab" <<EOF
#!/usr/bin/env bash
case "\$1" in
    -l) cat "$SPOOL" ;;
    *) grep -q GARBAGE "\$1" && { echo 'bad minute' >&2; exit 1; }
       cp "\$1" "$SPOOL"; echo installed >>"$WORK/installs" ;;
esac
EOF
    # nvim stand-in: records the +line it was given, appends \$FAKE_EDIT.
    cat >"$WORK/bin/nvim" <<EOF
#!/usr/bin/env bash
echo "\$1" >"$WORK/cursor"
[ -n "\${FAKE_EDIT:-}" ] && printf '%s\n' "\$FAKE_EDIT" >>"\$2"
exit 0
EOF
    chmod +x "$WORK/bin/crontab" "$WORK/bin/nvim"
    export PATH="$WORK/bin:$PATH"
}

@test "the cursor lands on the named job's line" {
    run "$EDIT" __backup_watchdog
    [ "$status" -eq 0 ]
    [ "$(cat "$WORK/cursor")" = "+5" ]
}

@test "a job name that is a prefix of another does not match the longer one" {
    run "$EDIT" __backup
    [ "$(cat "$WORK/cursor")" = "+2" ]
}

@test "no job opens on the first line" {
    run "$EDIT"
    [ "$(cat "$WORK/cursor")" = "+1" ]
}

@test "an unchanged buffer installs nothing" {
    run "$EDIT" __backup
    [ "$status" -eq 0 ]
    [[ "$output" == *"unchanged"* ]]
    [ ! -f "$WORK/installs" ]
}

@test "a changed buffer is installed" {
    FAKE_EDIT='# new line' run "$EDIT" __backup
    [ "$status" -eq 0 ]
    [ -f "$WORK/installs" ]
    grep -q '# new line' "$SPOOL"
}

@test "a rejected edit is kept for retry and the crontab stays as it was" {
    FAKE_EDIT='GARBAGE' run "$EDIT" __backup </dev/null
    [ "$status" -eq 1 ]
    [ ! -f "$WORK/installs" ]
    ! grep -q GARBAGE "$SPOOL"
    grep -q GARBAGE "$HOME/.local/state/cron-jobs/crontab.rejected"
}
