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
  # The drive layers: the WIP unit is not enabled and the drive job has not run unless a test says so.
  export DRIVE_MOUNT="$BATS_TEST_TMPDIR/nvme" DRIVE_UUID=fixture-uuid DRIVE_STATE_DIR="$BATS_TEST_TMPDIR/drive-state"
  cat > "$BATS_TEST_TMPDIR/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  is-enabled) [[ ${WIP_ENABLED:-0} == 1 ]] ;;
  is-active) [[ ${WIP_ACTIVE:-1} == 1 ]] ;;
  *) exit 1 ;;
esac
STUB
  cat > "$BATS_TEST_TMPDIR/bin/findmnt" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${WIP_FINDMNT-fixture-uuid btrfs}"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/restic" "$BATS_TEST_TMPDIR/bin/pgrep" "$BATS_TEST_TMPDIR/bin/systemctl" "$BATS_TEST_TMPDIR/bin/findmnt"
}

# Print the state column of the row for layer $1 (default wip), or nothing when there is no row.
wip_state() {
  awk -F' [|] ' -v layer="${1:-wip}" 'NF >= 5 { name = $1; gsub(/ +$/, "", name) } NF >= 5 && name == layer { gsub(/ +$/, "", $4); print $4 }' <<<"$output"
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

@test "wip layer has no row and no health metric before the unit is enabled" {
  run "$STATUS_SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(wip_state)" ]
  [[ "$output" == *"wip mirror: not installed"* ]]
  run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics.prom"
  grep -Fx 'backup_layer_installed{layer="wip"} 0' "$BATS_TEST_TMPDIR/metrics.prom"
  ! grep -F 'backup_layer_ok{layer="wip"}' "$BATS_TEST_TMPDIR/metrics.prom"
}

@test "an enabled unit with a missing or foreign drive shows unavailable" {
  export WIP_ENABLED=1
  mkdir -p "$DRIVE_MOUNT/wip/live" "$DRIVE_MOUNT/wip/versions"
  WIP_FINDMNT='' run "$STATUS_SCRIPT"
  [ "$(wip_state)" = unavailable ]
  WIP_FINDMNT='other-uuid btrfs' run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics.prom"
  grep -Fx 'backup_layer_installed{layer="wip"} 1' "$BATS_TEST_TMPDIR/metrics.prom"
  grep -Fx 'backup_layer_ok{layer="wip"} 0' "$BATS_TEST_TMPDIR/metrics.prom"
}

@test "an enabled drive reports missing trees, inactive unit, drill freshness and drill failure" {
  export WIP_ENABLED=1
  mkdir -p "$DRIVE_MOUNT/wip/live"
  run "$STATUS_SCRIPT"
  [ "$(wip_state)" = failed ]
  mkdir -p "$DRIVE_MOUNT/wip/versions"
  run "$STATUS_SCRIPT"
  [ "$(wip_state)" = unknown ]
  printf '{"last_run":%s,"layers":{"wip":{"ok":true,"last_run":%s,"last_success":%s}}}' "$(date +%s)" "$(date +%s)" "$(date +%s)" > "$HOME/.local/state/backup-drill/last.json"
  run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics.prom"
  grep -Fx 'backup_layer_ok{layer="wip"} 1' "$BATS_TEST_TMPDIR/metrics.prom"
  run "$STATUS_SCRIPT"
  [ "$(wip_state)" = ok ]
  WIP_ACTIVE=0 run "$STATUS_SCRIPT"
  [ "$(wip_state)" = inactive ]
  printf '{"last_run":1,"layers":{"wip":{"ok":true,"last_run":1,"last_success":1}}}' > "$HOME/.local/state/backup-drill/last.json"
  run "$STATUS_SCRIPT"
  [ "$(wip_state)" = stale ]
  printf '{"last_run":2,"layers":{"wip":{"ok":false,"last_run":2,"last_success":1}}}' > "$HOME/.local/state/backup-drill/last.json"
  run "$STATUS_SCRIPT"
  [ "$(wip_state)" = failed ]
}

@test "drive rows appear after the drive job succeeds and show a missing drive" {
  run "$STATUS_SCRIPT"
  [ -z "$(wip_state media)" ]
  [ -z "$(wip_state drive-restic)" ]
  mkdir -p "$DRIVE_STATE_DIR"
  date +%s > "$DRIVE_STATE_DIR/last-success"
  run "$STATUS_SCRIPT"
  [ "$(wip_state media)" = ok ]
  [ "$(wip_state drive-restic)" = ok ]
  WIP_FINDMNT='' run "$STATUS_SCRIPT" --prom "$BATS_TEST_TMPDIR/metrics.prom"
  grep -Fx 'backup_layer_ok{layer="media"} 0' "$BATS_TEST_TMPDIR/metrics.prom"
  WIP_FINDMNT='' run "$STATUS_SCRIPT"
  [ "$(wip_state media)" = unavailable ]
  [ "$(wip_state drive-restic)" = unavailable ]
}

@test "drive rows go stale, unknown or failed on their own evidence" {
  mkdir -p "$DRIVE_STATE_DIR"
  printf '1\n' > "$DRIVE_STATE_DIR/last-success"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/restic"
  run "$STATUS_SCRIPT"
  [ "$(wip_state media)" = stale ]
  [ "$(wip_state drive-restic)" = unknown ]
  date +%s > "$DRIVE_STATE_DIR/last-success"
  printf '{"last_run":2,"layers":{"media":{"ok":false,"last_run":2,"last_success":1}}}' > "$HOME/.local/state/backup-drill/last.json"
  run "$STATUS_SCRIPT"
  [ "$(wip_state media)" = failed ]
}
