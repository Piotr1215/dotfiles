#!/usr/bin/env bats

# __system_backup_rsync.sh must refuse to run when the NAS is not mounted, and off
# LAN it must send rsync over ssh through pop-os instead of the slow NFS relay.
# The preflight used `findmnt -T`, which resolves any path to the mount that
# contains it: an unmounted /mnt/nas-backup answered with / and passed (#181).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__system_backup_rsync.sh"
  WORK="$(mktemp -d)"
  CALLS="${WORK}/rsync-calls"

  # sudo runs the command unprivileged. rsync records each call and prints the
  # stats lines the retry loop reads back; the transport preflight (-n -d) exits
  # with $RSYNC_PREFLIGHT_RC so a test can play pop-os not answering.
  mkdir -p "${WORK}/bin"
  cat >"${WORK}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -n ] && shift
exec "$@"
EOF
  cat >"${WORK}/bin/rsync" <<EOF
#!/usr/bin/env bash
echo "rsync \$*" >>"${CALLS}"
case " \$* " in
  *" -n -d "*) exit "\${RSYNC_PREFLIGHT_RC:-0}" ;;
esac
echo "Number of regular files transferred: 0"
echo "Total transferred file size: 0 bytes"
EOF
  chmod +x "${WORK}/bin/sudo" "${WORK}/bin/rsync"
  export PATH="${WORK}/bin:${PATH}"

  export SYSTEM_BACKUP_PREFLIGHT_TIMEOUT=5
  export SYSTEM_BACKUP_RELAY_TARGET="relay.test:system-backup"
  export SYSTEM_BACKUP_RELAY_SSH="ssh-stub"
  # Off LAN unless a test calls on_lan: nothing listens on port 1.
  export SYSTEM_BACKUP_LAN_PROBE="127.0.0.1/1"
}

teardown() {
  [ -z "${LISTENER_PID:-}" ] || kill "$LISTENER_PID" 2>/dev/null || true
  [ -z "${SHM_DEST:-}" ] || rm -rf "$SHM_DEST"
  rm -rf "$WORK"
}

# on_lan: listen on a local port and point the LAN probe at it.
on_lan() {
  python3 -c 'import socket,time; s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(8); print(s.getsockname()[1], flush=True); time.sleep(120)' >"${WORK}/port" 3>&- &
  LISTENER_PID=$!
  for _ in $(seq 50); do [ -s "${WORK}/port" ] && break; sleep 0.1; done
  export SYSTEM_BACKUP_LAN_PROBE="127.0.0.1/$(cat "${WORK}/port")"
}

@test "on LAN a directory that is not a mount point fails preflight and never reaches rsync" {
  on_lan
  mkdir -p "${WORK}/nas"

  SYSTEM_BACKUP_MOUNT="${WORK}/nas" SYSTEM_BACKUP_DEST="${WORK}/nas/system-backup" run "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"transport: on LAN"* ]]
  [[ "$output" == *"preflight: ${WORK}/nas is not a mount point"* ]]
  [ ! -e "$CALLS" ]
  [ ! -e "${WORK}/nas/system-backup" ]
}

@test "on LAN a writable mount point passes preflight and rsync writes to the local destination" {
  on_lan
  SHM_DEST="$(mktemp -d /dev/shm/system-backup-test.XXXXXX)"

  SYSTEM_BACKUP_MOUNT=/dev/shm SYSTEM_BACKUP_DEST="$SHM_DEST" run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"preflight: /dev/shm is writable"* ]]
  [[ "$output" == *"SUMMARY: backup complete"* ]]
  [ "$(wc -l <"$CALLS")" -eq 1 ]
  grep -q -- "--chmod=D-t .* / ${SHM_DEST}\$" "$CALLS"
  [ "$(grep -c -- "-e ssh-stub" "$CALLS")" -eq 0 ]
}

@test "off LAN with pop-os answering, rsync goes over ssh to the relay and skips the NFS preflight" {
  mkdir -p "${WORK}/nas"

  SYSTEM_BACKUP_MOUNT="${WORK}/nas" SYSTEM_BACKUP_DEST="${WORK}/nas/system-backup" run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"transport: off LAN, rsync goes over ssh through pop-os"* ]]
  [[ "$output" != *"preflight:"* ]]
  [[ "$output" == *"SUMMARY: backup complete"* ]]
  grep -q -- "-n -d .* relay.test:system-backup/\$" "$CALLS"
  grep -q -- "--chmod=D-t .* -e ssh-stub / relay.test:system-backup\$" "$CALLS"
  [ ! -e "${WORK}/nas/system-backup" ]
}

@test "off LAN with pop-os not answering, it falls back to the NFS path and its preflight" {
  mkdir -p "${WORK}/nas"

  RSYNC_PREFLIGHT_RC=12 SYSTEM_BACKUP_MOUNT="${WORK}/nas" SYSTEM_BACKUP_DEST="${WORK}/nas/system-backup" run "$SCRIPT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"transport: off LAN and pop-os did not answer (rsync exit 12)"* ]]
  [[ "$output" == *"preflight: ${WORK}/nas is not a mount point"* ]]
  [ "$(wc -l <"$CALLS")" -eq 1 ]
}
