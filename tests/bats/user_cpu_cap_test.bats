#!/usr/bin/env bats

setup() {
  root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  export PATH="$bin:$PATH" CALLS="$BATS_TEST_TMPDIR/calls"
  export USER_CPU_CAP_CGROUP_FILE="$BATS_TEST_TMPDIR/cpu.max"
  cat > "$bin/nproc" <<'STUB'
#!/bin/sh
echo 24
STUB
  cat > "$bin/sudo" <<'STUB'
#!/bin/sh
printf 'sudo %s\n' "$*" >> "$CALLS"
exit "${SUDO_FAIL:-0}"
STUB
  cat > "$bin/tmux" <<'STUB'
#!/bin/sh
exit 1
STUB
  cat > "$bin/systemctl" <<'STUB'
#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$CALLS"
case "$*" in *show*) echo "${QUOTA_VALUE:-19.200000s}";; esac
STUB
  cat > "$bin/systemd-run" <<'STUB'
#!/bin/sh
printf 'systemd-run %s\n' "$*" >> "$CALLS"
STUB
  chmod +x "$bin"/*
}

@test 'status identifies exact cap, unlimited, and partial cap' {
  echo '1920000 100000' > "$USER_CPU_CAP_CGROUP_FILE"
  run "$root/scripts/__user_cpu_cap.sh" status
  [ "$status" -eq 0 ]
  echo 'max 100000' > "$USER_CPU_CAP_CGROUP_FILE"
  run "$root/scripts/__user_cpu_cap.sh" status
  [ "$status" -eq 1 ]
  echo '1000000 100000' > "$USER_CPU_CAP_CGROUP_FILE"
  run "$root/scripts/__user_cpu_cap.sh" status
  [ "$status" -eq 2 ]
  rm "$USER_CPU_CAP_CGROUP_FILE"
  run "$root/scripts/__user_cpu_cap.sh" status
  [ "$status" -eq 2 ]
  [ ! -e "$CALLS" ]
}

@test 'successful toggle clears only matching interim quota' {
  run "$root/scripts/__user_cpu_cap.sh" on
  [ "$status" -eq 0 ]
  grep -Fx 'sudo systemctl set-property user.slice CPUQuota=1920%' "$CALLS"
  grep -Fx 'systemctl --user set-property --runtime app.slice CPUQuota=' "$CALLS"
  : > "$CALLS"
  export QUOTA_VALUE=10.000000s
  run "$root/scripts/__user_cpu_cap.sh" off
  [ "$status" -eq 0 ]
  grep -Fx 'sudo systemctl set-property user.slice CPUQuota=' "$CALLS"
  run grep -q '^systemctl .*set-property' "$CALLS"
  [ "$status" -eq 1 ]
}

@test 'malformed kernel state and unknown commands fail without writes' {
  for value in '1920000 0' '1920000 nope' 'bad 100000' '1920000 100000 extra'; do
    echo "$value" > "$USER_CPU_CAP_CGROUP_FILE"
    run "$root/scripts/__user_cpu_cap.sh" status
    [ "$status" -eq 2 ]
  done
  run "$root/scripts/__user_cpu_cap.sh" surprise
  [ "$status" -eq 2 ]
  [ ! -e "$CALLS" ]
}

@test 'failed privileged toggle leaves interim limits untouched' {
  export SUDO_FAIL=1
  run "$root/scripts/__user_cpu_cap.sh" on
  [ "$status" -eq 1 ]
  run grep -q '^systemctl ' "$CALLS"
  [ "$status" -eq 1 ]
}

@test 'recovery uses session slice and elevated CPU weight' {
  run "$root/scripts/__user_cpu_cap.sh" recovery
  [ "$status" -eq 0 ]
  grep -Fx 'systemd-run --user --scope --slice=session.slice -p CPUWeight=10000 alacritty --title CPU recovery -e /usr/bin/bash --noprofile --norc' "$CALLS"
}

