#!/usr/bin/env bats

# __system_backup_rsync.sh must refuse to run when the NAS is not mounted. Its
# preflight used `findmnt -T`, which resolves any path to the mount containing
# it: an unmounted /mnt/nas-backup answered with / and passed, leaving only the
# write probe between rsync and the local disk (#181).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__system_backup_rsync.sh"
  WORK="$(mktemp -d)"
  CALLS="${WORK}/rsync-calls"

  # sudo runs the command unprivileged; rsync only records that it was reached
  # and prints the stats lines the retry loop reads back.
  mkdir -p "${WORK}/bin"
  cat >"${WORK}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -n ] && shift
exec "$@"
EOF
  cat >"${WORK}/bin/rsync" <<EOF
#!/usr/bin/env bash
echo "rsync \$*" >>"${CALLS}"
echo "Number of regular files transferred: 0"
echo "Total transferred file size: 0 bytes"
EOF
  chmod +x "${WORK}/bin/sudo" "${WORK}/bin/rsync"
  export PATH="${WORK}/bin:${PATH}"
  export SYSTEM_BACKUP_PREFLIGHT_TIMEOUT=5
}

teardown() {
  rm -rf "$WORK"
  [ -z "${SHM_DEST:-}" ] || rm -rf "$SHM_DEST"
}

@test "a directory that is not a mount point fails preflight and never reaches rsync" {
  mkdir -p "${WORK}/nas"

  SYSTEM_BACKUP_MOUNT="${WORK}/nas" SYSTEM_BACKUP_DEST="${WORK}/nas/system-backup" run "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"preflight: ${WORK}/nas is not a mount point"* ]]
  [ ! -e "$CALLS" ]
  [ ! -e "${WORK}/nas/system-backup" ]
}

@test "a writable mount point passes preflight and runs rsync into the destination" {
  SHM_DEST="$(mktemp -d /dev/shm/system-backup-test.XXXXXX)"

  SYSTEM_BACKUP_MOUNT=/dev/shm SYSTEM_BACKUP_DEST="$SHM_DEST" run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"preflight: /dev/shm is writable"* ]]
  [[ "$output" == *"SUMMARY: backup complete"* ]]
  grep -q " / ${SHM_DEST}\$" "$CALLS"
}
