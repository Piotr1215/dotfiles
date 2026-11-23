#!/usr/bin/env bats

# Prepare isolated producer logs, timestamps, drill results, and stubs.
setup() {
  export HOME="$BATS_TEST_TMPDIR/home" BACKUP_ROOT="$BATS_TEST_TMPDIR/nas" TMPDIR="$BATS_TEST_TMPDIR"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export STATUS_SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__backup_status.sh"
  mkdir -p "$HOME/.local/state/cron-jobs" "$HOME/.local/state/backup-drill" "$BACKUP_ROOT/taskwarrior-mirror" "$BATS_TEST_TMPDIR/bin"
  date +%s > "$HOME/.local/state/backup-last-success"
  date +%s > "$BACKUP_ROOT/taskwarrior-mirror/.dirs-ok-at"
  printf '[%s] [INFO] run end: exit=0 state=no-hit duration=1s\n' "$(date '+%F %T')" > "$HOME/.local/state/cron-jobs/__task_sync.log"
  printf '[%s] [INFO] Backup completed in 1s\n' "$(date '+%F %T')" > "$HOME/backup.log"
  printf '[%s] [INFO] SUMMARY: backup complete in 1s\n' "$(date '+%F %T')" > "$HOME/.local/state/cron-jobs/system-backup-rsync.log"
  cat > "$BATS_TEST_TMPDIR/bin/restic" <<'STUB'
#!/usr/bin/env bash
printf '[{"id":"x","time":"%s","paths":["%s/.local/share/task-backups"]}]\n' "$(date -Is)" "$HOME"
STUB
  cat > "$BATS_TEST_TMPDIR/bin/pgrep" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  # The drive layers: the drive job has not run unless a test says so.
  export DRIVE_MOUNT="$BATS_TEST_TMPDIR/nvme" DRIVE_UUID=fixture-uuid DRIVE_STATE_DIR="$BATS_TEST_TMPDIR/drive-state"
  cat > "$BATS_TEST_TMPDIR/bin/findmnt" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${DRIVE_FINDMNT-fixture-uuid btrfs}"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/restic" "$BATS_TEST_TMPDIR/bin/pgrep" "$BATS_TEST_TMPDIR/bin/findmnt"
}

# Print the state column of the row for layer $1, or nothing when there is no row.
layer_state() {
  awk -F' [|] ' -v layer="$1" 'NF >= 5 { name = $1; gsub(/ +$/, "", name) } NF >= 5 && name == layer { gsub(/ +$/, "", $4); print $4 }' <<<"$output"
}

@test "table uses producer timestamps and marks absent drill unknown" {
  run "$STATUS_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"restic        |"*"ok"* ]]
  [[ "$output" == *"taskchampion"*"unknown"* ]]
}

@test "latest component failures and hold are visible" {
  printf '[%s] [ERROR] 1 component(s) failed: dev folder: failed\n' "$(date '+%F %T')" >> "$HOME/backup.log"
  touch "$HOME/.local/state/backup-hold"
  run "$STATUS_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"held"* ]]
}

@test "metrics capture stale task and failed drill" {
  printf '1\n' > "$BACKUP_ROOT/taskwarrior-mirror/.dirs-ok-at"
  printf '{"last_run":123,"layers":{"home":{"ok":false,"last_run":123}}}' > "$HOME/.local/state/backup-drill/last.json"
  run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics/backup.prom"
  [ "$status" -eq 0 ]
  grep -Fx 'backup_layer_ok{layer="task-files"} 0' "$BATS_TEST_TMPDIR/metrics/backup.prom"
  grep -Fx 'backup_drill_ok{layer="home"} 0' "$BATS_TEST_TMPDIR/metrics/backup.prom"
  grep -Fx 'backup_drill_last_run_timestamp_seconds 123' "$BATS_TEST_TMPDIR/metrics/backup.prom"
  [ "$(find "$BATS_TEST_TMPDIR/metrics" -type f | wc -l)" -eq 1 ]
}

@test "sync and directory mirror timestamps are reported separately" {
  printf '1\n' > "$BACKUP_ROOT/taskwarrior-mirror/.ok-at"
  run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics.prom"
  [ "$status" -eq 0 ]
  grep -Fx 'backup_layer_ok{layer="task-files"} 1' "$BATS_TEST_TMPDIR/metrics.prom"
  grep -Fx 'backup_layer_ok{layer="task-sync"} 1' "$BATS_TEST_TMPDIR/metrics.prom"
  printf '[2000-01-01 00:00:00] [INFO] run end: exit=0 state=no-hit duration=1s\n' > "$HOME/.local/state/cron-jobs/__task_sync.log"
  printf '[%s] [ERROR] run end: exit=1 state=error duration=1s\n' "$(date '+%F %T')" >> "$HOME/.local/state/cron-jobs/__task_sync.log"
  run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics.prom"
  [ "$status" -eq 0 ]
  grep -Fx 'backup_layer_ok{layer="task-files"} 1' "$BATS_TEST_TMPDIR/metrics.prom"
  grep -Fx 'backup_layer_ok{layer="task-sync"} 0' "$BATS_TEST_TMPDIR/metrics.prom"
}

@test "exporter reports an enabled textfile directory" {
  printf '#!/usr/bin/env bash\necho "123 node_exporter --collector.textfile.directory=/fixture/metrics"\n' > "$BATS_TEST_TMPDIR/bin/pgrep"
  run "$STATUS_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"textfile directory: /fixture/metrics"* ]]
}

@test "missing restic output is unknown, not healthy" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/restic"
  run "$STATUS_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown"* ]]
}

@test "a newer component success is shown even if another component fails" {
  printf '[%s] [INFO] system files backup completed successfully\n' "$(date '+%F %T')" >> "$HOME/backup.log"
  printf '[%s] [ERROR] 1 component(s) failed: dev folder: failed\n' "$(date '+%F %T')" >> "$HOME/backup.log"
  run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics.prom"
  [ "$status" -eq 0 ]
  grep -Fx 'backup_layer_ok{layer="home"} 1' "$BATS_TEST_TMPDIR/metrics.prom"
  grep -Fx 'backup_layer_ok{layer="dev"} 0' "$BATS_TEST_TMPDIR/metrics.prom"
}

@test "a hold is exported without treating mirror status as healthy" {
  touch "$HOME/.local/state/backup-hold"
  run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics.prom"
  [ "$status" -eq 0 ]
  grep -Fx 'backup_hold_active 1' "$BATS_TEST_TMPDIR/metrics.prom"
  grep -Fx 'backup_layer_ok{layer="home"} 0' "$BATS_TEST_TMPDIR/metrics.prom"
}

@test "textfile directory alone is not enabled when default collectors are disabled" {
  printf '#!/usr/bin/env bash\necho "123 node_exporter --collector.disable-defaults --collector.textfile.directory=/fixture/metrics"\n' > "$BATS_TEST_TMPDIR/bin/pgrep"
  run "$STATUS_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not enabled"* ]]
}

@test "prom without a path uses the default state directory" {
  run "$STATUS_SCRIPT" --prom
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/state/backup-status/backup.prom" ]
}

@test "failed server drill retains the timestamp of its last success" {
  printf '{"last_run":456,"layers":{"taskchampion":{"ok":false,"last_run":456,"last_success":123}}}' > "$HOME/.local/state/backup-drill/last.json"
  run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics.prom"
  [ "$status" -eq 0 ]
  grep -Fx 'backup_layer_last_success_timestamp_seconds{layer="taskchampion"} 123' "$BATS_TEST_TMPDIR/metrics.prom"
  grep -Fx 'backup_layer_ok{layer="taskchampion"} 0' "$BATS_TEST_TMPDIR/metrics.prom"
}

@test "drive rows appear after the drive job succeeds and show a missing drive" {
  run "$STATUS_SCRIPT"
  [ -z "$(layer_state media)" ]
  [ -z "$(layer_state drive-restic)" ]
  mkdir -p "$DRIVE_STATE_DIR"
  date +%s > "$DRIVE_STATE_DIR/last-success"
  run "$STATUS_SCRIPT"
  [ "$(layer_state media)" = ok ]
  [ "$(layer_state drive-restic)" = ok ]
  DRIVE_FINDMNT='' run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics.prom"
  grep -Fx 'backup_layer_ok{layer="media"} 0' "$BATS_TEST_TMPDIR/metrics.prom"
  DRIVE_FINDMNT='' run "$STATUS_SCRIPT"
  [ "$(layer_state media)" = unavailable ]
  [ "$(layer_state drive-restic)" = unavailable ]
}

@test "drive rows go stale, unknown or failed on their own evidence" {
  mkdir -p "$DRIVE_STATE_DIR"
  printf '1\n' > "$DRIVE_STATE_DIR/last-success"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/restic"
  run "$STATUS_SCRIPT"
  [ "$(layer_state media)" = stale ]
  [ "$(layer_state drive-restic)" = unknown ]
  date +%s > "$DRIVE_STATE_DIR/last-success"
  printf '{"last_run":2,"layers":{"media":{"ok":false,"last_run":2,"last_success":1}}}' > "$HOME/.local/state/backup-drill/last.json"
  run "$STATUS_SCRIPT"
  [ "$(layer_state media)" = failed ]
}

@test "the weekly server restore counts for 8 days and undrilled layers get no drill metric" {
  now=$(date +%s)
  printf '{"last_run":%s,"layers":{"taskchampion":{"ok":true,"last_run":%s,"last_success":%s}}}' "$now" "$((now - 6 * 86400))" "$((now - 6 * 86400))" > "$HOME/.local/state/backup-drill/last.json"
  run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics.prom"
  [ "$status" -eq 0 ]
  grep -Fx 'backup_layer_ok{layer="taskchampion"} 1' "$BATS_TEST_TMPDIR/metrics.prom"
  grep -Fx 'backup_drill_ok{layer="taskchampion"} 1' "$BATS_TEST_TMPDIR/metrics.prom"
  run grep -F 'backup_drill_ok{layer="task-sync"}' "$BATS_TEST_TMPDIR/metrics.prom"
  [ "$status" -eq 1 ]
  printf '{"last_run":%s,"layers":{"taskchampion":{"ok":true,"last_run":%s,"last_success":%s}}}' "$now" "$((now - 9 * 86400))" "$((now - 9 * 86400))" > "$HOME/.local/state/backup-drill/last.json"
  run "$STATUS_SCRIPT"
  [ "$(layer_state taskchampion)" = stale ]
}

@test "the removed wip mirror gets no row or metric, even with an old drill result" {
  mkdir -p "$DRIVE_MOUNT/wip/live" "$DRIVE_MOUNT/wip/versions"
  printf '{"last_run":%s,"layers":{"wip":{"ok":true,"last_run":%s,"last_success":%s}}}' "$(date +%s)" "$(date +%s)" "$(date +%s)" > "$HOME/.local/state/backup-drill/last.json"
  run "$STATUS_SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(layer_state wip)" ]
  [[ "$output" != *"wip mirror"* ]]
  run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics.prom"
  ! grep -F 'layer="wip"' "$BATS_TEST_TMPDIR/metrics.prom"
}
