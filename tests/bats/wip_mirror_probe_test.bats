#!/usr/bin/env bats

# Isolated home, drive and stubs; the "mirror" is a background copier a test starts.
setup() {
  export HOME="$BATS_TEST_TMPDIR/home" PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export DRIVE_MOUNT="$BATS_TEST_TMPDIR/nvme" WIP_PROBE_TIMEOUT=3 CALLS="$BATS_TEST_TMPDIR/calls"
  export PROBE_SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__wip_mirror_probe.sh"
  mkdir -p "$HOME/dev" "$BATS_TEST_TMPDIR/bin" "$CALLS"
  cat > "$BATS_TEST_TMPDIR/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == is-enabled && ${WIP_ENABLED:-1} == 1 ]]
STUB
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS/curl"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/systemctl" "$BATS_TEST_TMPDIR/bin/curl"
  copy="$DRIVE_MOUNT/wip/live$HOME/dev/.wip-mirror-probe"
}

teardown() {
  [[ -n "${copier:-}" ]] && kill "$copier" 2>/dev/null || true
}

# Copy the probe file to its drive path every 0.2 s, like a working mirror.
start_mirror() {
  mkdir -p "$(dirname "$copy")"
  ( while :; do cp "$HOME/dev/.wip-mirror-probe" "$copy" 2>/dev/null || true; sleep 0.2; done ) &
  copier=$!
}

@test "a save that reaches the drive writes the success stamp" {
  start_mirror
  run bash "$PROBE_SCRIPT"
  [ "$status" -eq 0 ]
  [ -s "$HOME/.local/state/wip-probe/last-success" ]
  [ ! -e "$CALLS/curl" ]
}

@test "a stale copy on the drive does not count as a new save" {
  mkdir -p "$(dirname "$copy")"
  printf 'old nonce\n' > "$copy"
  run bash "$PROBE_SCRIPT"
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.local/state/wip-probe/last-success" ]
}

@test "a stalled mirror pages once a day and leaves no stamp" {
  run bash "$PROBE_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"probe not on the drive after 3 s"* ]]
  [ "$(wc -l < "$CALLS/curl")" -eq 1 ]
  grep -q 'WIP mirror stalled' "$CALLS/curl"
  run bash "$PROBE_SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$CALLS/curl")" -eq 1 ]
  [ ! -e "$HOME/.local/state/wip-probe/last-success" ]
}

@test "no probe while the unit is not enabled" {
  WIP_ENABLED=0 run bash "$PROBE_SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/dev/.wip-mirror-probe" ]
  [ ! -e "$CALLS/curl" ]
}
