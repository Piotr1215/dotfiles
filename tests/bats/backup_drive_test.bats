#!/usr/bin/env bats

# Exercise the drive backup with temporary sources and stubbed privileged commands.
setup() {
  export HOME="$BATS_TEST_TMPDIR/home" DRIVE_MOUNT="$BATS_TEST_TMPDIR/drive"
  export NAS_REPO="$BATS_TEST_TMPDIR/nas-repo" DRIVE_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export BACKUP_HOLD_FILE="$BATS_TEST_TMPDIR/hold" TMPDIR="$BATS_TEST_TMPDIR"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export DRIVE_SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__backup_drive.sh"
  export MEDIA_SOURCES="$BATS_TEST_TMPDIR/photos:$BATS_TEST_TMPDIR/videos" SNAPSHOT_KEEP=3
  export CALLS_DIR="$BATS_TEST_TMPDIR/calls"
  export NIGHTLY_LOCK_FILE="$BATS_TEST_TMPDIR/backup.lock" BACKUP_NTFY_URL=https://ntfy.invalid/topic
  unset RESTIC_REPOSITORY RESTIC_PASSWORD RESTIC_PASSWORD_FILE
  export RESTIC_PASSWORD_FILE="$BATS_TEST_TMPDIR/restic-password"
  printf 'test password\n' > "$RESTIC_PASSWORD_FILE"
  mkdir -p "$HOME" "$NAS_REPO" "$DRIVE_STATE_DIR" "$CALLS_DIR" "$BATS_TEST_TMPDIR/bin" \
    "$DRIVE_MOUNT/media" "$DRIVE_MOUNT/restic/secure-store" "$DRIVE_MOUNT/snapshots" \
    "$BATS_TEST_TMPDIR/photos" "$BATS_TEST_TMPDIR/videos"
  printf 'photo\n' > "$BATS_TEST_TMPDIR/photos/one"
  printf 'video\n' > "$BATS_TEST_TMPDIR/videos/two"
  cat > "$BATS_TEST_TMPDIR/bin/findmnt" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_FINDMNT-d74106d0-1b12-4d65-873d-d69ed3a729e6 btrfs}"
STUB
  cat > "$BATS_TEST_TMPDIR/bin/restic" <<'STUB'
#!/usr/bin/env bash
printf '%s ' "$@" >> "$CALLS_DIR/restic"
printf '\n' >> "$CALLS_DIR/restic"
[[ ${RESTIC_REPOSITORY+x} || ${RESTIC_PASSWORD+x} ]] && exit 91
for arg in "$@"; do
  [[ $arg == copy ]] && exit "${RESTIC_FAIL:-0}"
done
exit 0
STUB
  cat > "$BATS_TEST_TMPDIR/bin/sudo" <<'STUB'
#!/usr/bin/env bash
printf '%s ' "$@" >> "$CALLS_DIR/sudo"
printf '\n' >> "$CALLS_DIR/sudo"
drive=$(realpath -m -- "$DRIVE_MOUNT") || exit 1
if [[ $# == 7 && $1 == -n && $2 == btrfs && $3 == subvolume && $4 == snapshot && $5 == -r ]]; then
  src=$(realpath -m -- "$6") || exit 1
  dst=$(realpath -m -- "$7") || exit 1
  [[ $src == "$drive/"* && $dst == "$drive/"* ]] || exit 1
  [[ ${FAIL_SNAPSHOT:-} == "$(basename "$6")" ]] && exit 1
  mkdir -p -- "$dst"
elif [[ $# == 5 && $1 == -n && $2 == btrfs && $3 == subvolume && $4 == delete ]]; then
  target=$(realpath -m -- "$5") || exit 1
  [[ $target == "$drive/snapshots/"* ]] || exit 1
  [[ ${FAIL_DELETE:-} == "$(basename "$5")" ]] && exit 1
  rm -rf -- "$target"
else
  exit 1
fi
STUB
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${@: -2:1}" >> "$CALLS_DIR/curl"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/findmnt" "$BATS_TEST_TMPDIR/bin/restic" "$BATS_TEST_TMPDIR/bin/sudo" "$BATS_TEST_TMPDIR/bin/curl"
}

@test "wrong UUID and empty mount identity stop before any backup activity" {
  for identity in 'wrong-uuid btrfs' ''; do
    export FAKE_FINDMNT="$identity"
    run bash "$DRIVE_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *ERROR* ]]
    [[ "$output" == *"drive not mounted at $DRIVE_MOUNT with the expected UUID d74106d0-1b12-4d65-873d-d69ed3a729e6"* ]]
    [ ! -e "$CALLS_DIR/restic" ]
    [ ! -e "$CALLS_DIR/sudo" ]
    [ -z "$(ls -A "$DRIVE_MOUNT/media")" ]
  done
}

@test "clean run mirrors sources, copies restic, snapshots both and stamps success" {
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$DRIVE_MOUNT/media/photos/one")" = photo ]
  [ "$(cat "$DRIVE_MOUNT/media/videos/two")" = video ]
  grep -E -- "(^| )-r $DRIVE_MOUNT/restic/secure-store .*copy .*--from-repo $NAS_REPO( |$)" "$CALLS_DIR/restic"
  grep -E -- "(^| )-r $DRIVE_MOUNT/restic/secure-store .*forget( |$)" "$CALLS_DIR/restic"
  grep -F -- "-r $DRIVE_MOUNT/restic/secure-store --password-file $RESTIC_PASSWORD_FILE copy --from-repo $NAS_REPO --from-password-file $RESTIC_PASSWORD_FILE --retry-lock 30m " "$CALLS_DIR/restic"
  grep -F -- "-r $DRIVE_MOUNT/restic/secure-store --password-file $RESTIC_PASSWORD_FILE forget --retry-lock 30m --group-by host,tags --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --keep-tag keep --keep-tag browser-profiles-2026-09-11 --keep-tag homelab-envrc --prune " "$CALLS_DIR/restic"
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'media@*' | wc -l)" -eq 1 ]
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'restic@*' | wc -l)" -eq 1 ]
  for kind in media restic; do
    name=$(basename "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name "$kind@*")")
    [[ "$name" =~ ^${kind}@[0-9]{8}T[0-9]{6}$ ]]
  done
  [[ "$(cat "$DRIVE_STATE_DIR/last-success")" =~ ^[0-9]+$ ]]
}

@test "snapshot retention keeps the newest configured number of each kind" {
  for kind in media restic; do
    for day in 01 02 03 04; do
      mkdir -p "$DRIVE_MOUNT/snapshots/$kind@200001${day}T000000"
    done
  done
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 0 ]
  for kind in media restic; do
    [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name "$kind@*" | wc -l)" -eq "$SNAPSHOT_KEEP" ]
    [ ! -e "$DRIVE_MOUNT/snapshots/$kind@20000101T000000" ]
    [ ! -e "$DRIVE_MOUNT/snapshots/$kind@20000102T000000" ]
    [ -d "$DRIVE_MOUNT/snapshots/$kind@20000103T000000" ]
    [ -d "$DRIVE_MOUNT/snapshots/$kind@20000104T000000" ]
  done
}

@test "restic copy failure preserves media snapshot and reports failure" {
  export RESTIC_FAIL=1
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *SUMMARY*FAILED*restic* ]]
  grep -E '(^| )forget( |$)' "$CALLS_DIR/restic"
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'media@*' | wc -l)" -eq 1 ]
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'restic@*' | wc -l)" -eq 0 ]
  [ ! -e "$DRIVE_STATE_DIR/last-success" ]
}

@test "hold skips media mirror but still copies restic" {
  printf 'restore in progress\n' > "$BACKUP_HOLD_FILE"
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *WARNING* ]]
  [ -z "$(ls -A "$DRIVE_MOUNT/media")" ]
  grep -E '(^| )copy( |$)' "$CALLS_DIR/restic"
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'media@*' | wc -l)" -eq 0 ]
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'restic@*' | wc -l)" -eq 1 ]
  [ ! -e "$DRIVE_STATE_DIR/last-success" ]
}

@test "a second run while one holds the lock skips with 75 and touches nothing" {
  exec 9>>"$TMPDIR/backup-drive.lock"
  flock -n 9
  run bash "$DRIVE_SCRIPT"
  exec 9>&-
  [ "$status" -eq 75 ]
  [[ "$output" == *'skipping'* ]]
  [ ! -e "$CALLS_DIR/restic" ]
  [ -z "$(ls -A "$DRIVE_MOUNT/media")" ]
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "mass source deletion parks removed files in the mirror attic" {
  mkdir -p "$DRIVE_MOUNT/media/photos"
  for n in one two three; do printf '%s\n' "$n" > "$DRIVE_MOUNT/media/photos/$n"; done
  rm "$BATS_TEST_TMPDIR/photos/one"
  export BACKUP_MAX_DELETES=1
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *WARNING*3* ]]
  for n in one two three; do
    [ ! -e "$DRIVE_MOUNT/media/photos/$n" ]
    [ "$(find "$DRIVE_MOUNT/media/photos/.attic" -type f -name "$n" | wc -l)" -eq 1 ]
  done
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 0 ]
  for n in one two three; do
    [ "$(find "$DRIVE_MOUNT/media/photos/.attic" -type f -name "$n" | wc -l)" -eq 1 ]
  done
}

@test "missing media source warns and mirrors remaining source" {
  rm -r "$BATS_TEST_TMPDIR/photos"
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *WARNING* ]]
  [ "$(cat "$DRIVE_MOUNT/media/videos/two")" = video ]
}

@test "help and invalid arguments do not start backup activity" {
  run bash "$DRIVE_SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *Usage:* ]]
  run bash "$DRIVE_SCRIPT" --invalid
  [ "$status" -eq 2 ]
  [[ "$output" == *Usage:* ]]
  [ ! -e "$CALLS_DIR/restic" ]
  [ ! -e "$CALLS_DIR/sudo" ]
  [ -z "$(ls -A "$DRIVE_MOUNT/media")" ]
}

@test "inherited restic repository and password do not reach restic" {
  export RESTIC_REPOSITORY=wrong-repository RESTIC_PASSWORD=wrong-password
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 0 ]
  grep -E '(^| )copy( |$)' "$CALLS_DIR/restic"
}

@test "one failed media mirror prevents a snapshot after both sources are attempted" {
  cat > "$BATS_TEST_TMPDIR/bin/rsync" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS_DIR/rsync"
for arg in "$@"; do
  [[ $arg == "$BATS_TEST_TMPDIR/photos/" ]] && exit 1
done
exec /usr/bin/rsync "$@"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/rsync"
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *SUMMARY*FAILED*media* ]]
  grep -F "$BATS_TEST_TMPDIR/photos/" "$CALLS_DIR/rsync"
  grep -F "$BATS_TEST_TMPDIR/videos/" "$CALLS_DIR/rsync"
  [ "$(cat "$DRIVE_MOUNT/media/videos/two")" = video ]
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'media@*' | wc -l)" -eq 0 ]
  grep -E '(^| )copy( |$)' "$CALLS_DIR/restic"
  [ ! -e "$DRIVE_STATE_DIR/last-success" ]
}

@test "failed snapshot is reported and the other snapshot is attempted" {
  export FAIL_SNAPSHOT=media
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *SUMMARY*FAILED*media*snapshot* ]]
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'media@*' | wc -l)" -eq 0 ]
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'restic@*' | wc -l)" -eq 1 ]
  [ ! -e "$DRIVE_STATE_DIR/last-success" ]
}

@test "retention continues deleting expired snapshots after one deletion fails" {
  export SNAPSHOT_KEEP=1 FAIL_DELETE='media@20000101T000000'
  mkdir -p "$DRIVE_MOUNT/snapshots/$FAIL_DELETE" "$DRIVE_MOUNT/snapshots/media@20000102T000000" "$DRIVE_MOUNT/snapshots/restic@20000101T000000"
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *SUMMARY*FAILED*media*snapshot* ]]
  [ -d "$DRIVE_MOUNT/snapshots/$FAIL_DELETE" ]
  [ ! -e "$DRIVE_MOUNT/snapshots/media@20000102T000000" ]
  [ ! -e "$DRIVE_MOUNT/snapshots/restic@20000101T000000" ]
  [ ! -e "$DRIVE_STATE_DIR/last-success" ]
}

@test "error log lines go to stdout" {
  export FAKE_FINDMNT='wrong-uuid btrfs'
  run bash -c 'bash "$DRIVE_SCRIPT" > "$BATS_TEST_TMPDIR/stdout" 2> "$BATS_TEST_TMPDIR/stderr"'
  [ "$status" -eq 1 ]
  grep -F '[ERROR] drive not mounted' "$BATS_TEST_TMPDIR/stdout"
  [ ! -s "$BATS_TEST_TMPDIR/stderr" ]
}

@test "invalid state destination reports failure after both snapshots" {
  export DRIVE_STATE_DIR="$BATS_TEST_TMPDIR/state-file"
  printf 'not a directory\n' > "$DRIVE_STATE_DIR"
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *SUMMARY*FAILED*success*stamp* ]]
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'media@*' | wc -l)" -eq 1 ]
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'restic@*' | wc -l)" -eq 1 ]
}

@test "unreadable snapshots directory fails retention while restic still runs" {
  chmod 300 "$DRIVE_MOUNT/snapshots"
  run bash "$DRIVE_SCRIPT"
  chmod 700 "$DRIVE_MOUNT/snapshots"
  [ "$status" -eq 1 ]
  [[ "$output" == *SUMMARY*FAILED* ]]
  [[ "$output" == *snapshot* ]]
  grep -E '(^| )copy( |$)' "$CALLS_DIR/restic"
  [ ! -e "$DRIVE_STATE_DIR/last-success" ]
}

@test "invalid delete limit skips media but still copies and snapshots restic" {
  export BACKUP_MAX_DELETES=invalid
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *SUMMARY*FAILED* ]]
  [ -z "$(ls -A "$DRIVE_MOUNT/media")" ]
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'media@*' | wc -l)" -eq 0 ]
  grep -E '(^| )copy( |$)' "$CALLS_DIR/restic"
  [ "$(find "$DRIVE_MOUNT/snapshots" -maxdepth 1 -type d -name 'restic@*' | wc -l)" -eq 1 ]
  [ ! -e "$DRIVE_STATE_DIR/last-success" ]
}

@test "invalid snapshot retention still mirrors media and copies restic" {
  export SNAPSHOT_KEEP=invalid
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *SUMMARY*FAILED* ]]
  [ "$(cat "$DRIVE_MOUNT/media/photos/one")" = photo ]
  [ "$(cat "$DRIVE_MOUNT/media/videos/two")" = video ]
  grep -E '(^| )copy( |$)' "$CALLS_DIR/restic"
  [ "$(find "$DRIVE_MOUNT/snapshots" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 0 ]
  [ ! -e "$DRIVE_STATE_DIR/last-success" ]
}

@test "leading-zero numeric limits are interpreted as decimal" {
  export SNAPSHOT_KEEP=03 BACKUP_MAX_DELETES=08
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$DRIVE_MOUNT/media/photos/one")" = photo ]
  grep -E '(^| )copy( |$)' "$CALLS_DIR/restic"
  [ "$(find "$DRIVE_MOUNT/snapshots" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 2 ]
  [[ "$(cat "$DRIVE_STATE_DIR/last-success")" =~ ^[0-9]+$ ]]
}

@test "a running nightly NAS backup makes the drive job skip with 75" {
  sleep 30 &
  printf '%s\n' "$!" > "$NIGHTLY_LOCK_FILE"
  run bash "$DRIVE_SCRIPT"
  kill "$!" 2>/dev/null || true
  [ "$status" -eq 75 ]
  [[ "$output" == *'nightly NAS backup is running'* ]]
  [ ! -e "$CALLS_DIR/restic" ]
  printf '999999999\n' > "$NIGHTLY_LOCK_FILE"
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "a failure pages ntfy once a day for the same cause" {
  export FAKE_FINDMNT=''
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 1 ]
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$CALLS_DIR/curl")" -eq 1 ]
  grep -Fx 'serval: drive backup failed: drive not mounted' "$CALLS_DIR/curl"
  unset FAKE_FINDMNT
  export RESTIC_FAIL=1
  run bash "$DRIVE_SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$CALLS_DIR/curl")" -eq 2 ]
  grep -F 'restic copy' "$CALLS_DIR/curl"
}
