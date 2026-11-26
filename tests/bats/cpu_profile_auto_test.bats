#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__cpu_profile_auto.sh"
  WORK=$(mktemp -d)
  export WORK
  export CPU_PROFILE_AUTO_SNAPSHOT="$WORK/current.json"
  export CPU_PROFILE_AUTO_POWER_SUPPLY_DIR="$WORK/power_supply"
  export CPU_PROFILE_AUTO_STATE_DIR="$WORK/state"
  export CPU_PROFILE_AUTO_TEST_HOOK="$WORK/before-tick.sh"
  export CPU_PROFILE_AUTO_TEST_START=1800000000
  export TEST_EPOCH=1800000000
  export TEST_PROFILE="$WORK/profile" TEST_CLOCK="$WORK/clock"
  export TEST_SETS="$WORK/sets" TEST_READS="$WORK/reads"
  mkdir -p "$WORK/bin" "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/AC" \
    "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/BAT0" "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/USB0"
  printf 'Mains\n' > "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/AC/type"
  printf '1\n' > "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/AC/online"
  printf 'Battery\n' > "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/BAT0/type"
  printf 'USB\n' > "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/USB0/type"
  printf '0\n' > "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/USB0/online"
  printf 'Balanced\n' > "$TEST_PROFILE"
  : > "$TEST_SETS"
  : > "$TEST_READS"

  cat > "$WORK/bin/system76-power" <<'EOF'
#!/usr/bin/env bash
set -e
IFS= read -r now < "$TEST_CLOCK"
[[ $1 == profile ]] || exit 1
if [[ $# == 1 ]]; then
  printf '%s\n' "$now" >> "$TEST_READS"
  IFS= read -r profile < "$TEST_PROFILE"
  printf 'Power Profile: %s\n' "$profile"
else
  printf '%s %s\n' "$now" "$2" >> "$TEST_SETS"
  [[ ${TEST_SET_FAIL:-0} == 0 ]] || exit 1
  case $2 in
    performance) printf 'Performance\n' > "$TEST_PROFILE" ;;
    balanced) printf 'Balanced\n' > "$TEST_PROFILE" ;;
    *) exit 1 ;;
  esac
  # The real setter applies the CPU profile, then exits 1 on a missing SCSI
  # host link power file (serval, 26 Nov 2026).
  [[ ${TEST_SET_PARTIAL:-0} == 0 ]] || exit 1
fi
EOF
  chmod +x "$WORK/bin/system76-power"
  # The setter is the power-profiles D-Bus interface GNOME reads; it applies the
  # same system76 profile and records it in the same file as the CLI stub.
  export TEST_BUSCTL="$WORK/busctl.calls"
  cat > "$WORK/bin/busctl" <<'EOF'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$TEST_BUSCTL"
IFS= read -r now < "$TEST_CLOCK"
[[ $* == '--system set-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile s '* ]] || exit 1
value=${!#}
printf '%s %s\n' "$now" "$value" >> "$TEST_SETS"
[[ ${TEST_SET_FAIL:-0} == 0 ]] || exit 1
case $value in
  performance) printf 'Performance\n' > "$TEST_PROFILE" ;;
  balanced) printf 'Balanced\n' > "$TEST_PROFILE" ;;
  *) exit 1 ;;
esac
[[ ${TEST_SET_PARTIAL:-0} == 0 ]] || exit 1
EOF
  chmod +x "$WORK/bin/busctl"
  export TEST_NOTES="$WORK/notes"
  : > "$TEST_NOTES"
  cat > "$WORK/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_NOTES"
[[ ${TEST_NOTIFY_FAIL:-0} == 0 ]]
EOF
  chmod +x "$WORK/bin/notify-send"
  # Never the real sysfs file or the real sudo: serval's sudo is passwordless.
  export CPU_PROFILE_AUTO_TCC_FILE="$WORK/tcc_offset"
  printf '13\n' > "$CPU_PROFILE_AUTO_TCC_FILE"
  cat > "$WORK/bin/sudo" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -n ]] && shift
[[ ${TEST_SUDO_FAIL:-0} == 0 ]] || exit 1
exec "$@"
EOF
  chmod +x "$WORK/bin/sudo"
  export PATH="$WORK/bin:$PATH"

  cat > "$CPU_PROFILE_AUTO_TEST_HOOK" <<'EOF'
cpu_profile_test_before_tick() {
  local now=$1 elapsed=$(( $1 - TEST_EPOCH )) busy=${TEST_BUSY:-45} age=${TEST_AGE:-0} stamp
  printf '%s\n' "$now" > "$TEST_CLOCK"
  if [[ ${TEST_PROFILE_CHANGE_AT:-none} == "$elapsed" ]]; then
    printf '%s\n' "$TEST_PROFILE_CHANGE_TO" > "$TEST_PROFILE"
  fi
  if [[ -n ${TEST_BUSY_CHANGE_AT:-} ]] && (( elapsed >= TEST_BUSY_CHANGE_AT )); then
    busy=$TEST_BUSY_CHANGE_TO
  fi
  if [[ ${TEST_STALE_AT:-none} == "$elapsed" ]]; then
    age=31
  fi
  if [[ ${TEST_BAD_JSON_AT:-none} == "$elapsed" ]]; then
    printf '{broken\n' > "$CPU_PROFILE_AUTO_SNAPSHOT"
    return
  fi
  if [[ ${TEST_TIME_OFFSET:-} == plus ]]; then
    stamp=$(date -u -d "@$((now - age + 3600))" '+%Y-%m-%dT%H:%M:%S')
    stamp="${stamp}${TEST_FRACTION:-}+01:00"
  elif [[ ${TEST_TIME_OFFSET:-} == minus ]]; then
    stamp=$(date -u -d "@$((now - age - 18000))" '+%Y-%m-%dT%H:%M:%S')
    stamp="${stamp}${TEST_FRACTION:-}-05:00"
  else
    stamp=$(date -u -d "@$((now - age))" '+%Y-%m-%dT%H:%M:%S')
    stamp="${stamp}${TEST_FRACTION:-}Z"
  fi
  printf '{"time":"%s","cpu":{"busy_percent":%s}}\n' "$stamp" "$busy" > "$CPU_PROFILE_AUTO_SNAPSHOT"
}
EOF
}

teardown() {
  rm -rf "$WORK"
}

@test "45 percent for 120 seconds switches Balanced to Performance" {
  export CPU_PROFILE_AUTO_TEST_TICKS=13
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000120 performance' ]
  [[ $output == *'switched to Performance; busy 120s=45.00%'* ]]
}

@test "35 percent does not switch up" {
  export CPU_PROFILE_AUTO_TEST_TICKS=19 TEST_BUSY=35
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "a full window is required before either switch" {
  export CPU_PROFILE_AUTO_TEST_TICKS=12
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
  printf 'Performance\n' > "$TEST_PROFILE"
  rm "$CPU_PROFILE_AUTO_STATE_DIR/state"
  export CPU_PROFILE_AUTO_TEST_TICKS=30 TEST_BUSY=10
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "one high sample does not replace the window mean" {
  export CPU_PROFILE_AUTO_TEST_TICKS=13 TEST_BUSY=0 TEST_BUSY_CHANGE_AT=120 TEST_BUSY_CHANGE_TO=100
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "10 percent for 300 seconds switches Performance to Balanced" {
  export CPU_PROFILE_AUTO_TEST_TICKS=31 TEST_BUSY=10
  printf 'Performance\n' > "$TEST_PROFILE"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000300 balanced' ]
  [[ $output == *'300s=10.00%'* ]]
}

@test "Battery profile is never changed under sustained load" {
  export CPU_PROFILE_AUTO_TEST_TICKS=37
  printf 'Battery\n' > "$TEST_PROFILE"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "an unknown profile is never changed" {
  export CPU_PROFILE_AUTO_TEST_TICKS=19
  printf 'Unknown\n' > "$TEST_PROFILE"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "USB online blocks a switch even when AC is online" {
  export CPU_PROFILE_AUTO_TEST_TICKS=19
  printf '1\n' > "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/USB0/online"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "battery power blocks a switch" {
  export CPU_PROFILE_AUTO_TEST_TICKS=19
  printf '0\n' > "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/AC/online"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "USB online also blocks the down switch" {
  export CPU_PROFILE_AUTO_TEST_TICKS=31 TEST_BUSY=10
  printf 'Performance\n' > "$TEST_PROFILE"
  printf '1\n' > "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/USB0/online"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "unknown USB state or supply type blocks a switch" {
  export CPU_PROFILE_AUTO_TEST_TICKS=13
  rm "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/USB0/online"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
  printf '0\n' > "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/USB0/online"
  rm "$CPU_PROFILE_AUTO_POWER_SUPPLY_DIR/USB0/type"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "snapshots older than 30 seconds never cause a switch" {
  export CPU_PROFILE_AUTO_TEST_TICKS=37 TEST_AGE=31
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "a 30 second old snapshot is still accepted" {
  export CPU_PROFILE_AUTO_TEST_TICKS=13 TEST_AGE=30
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000120 performance' ]
}

@test "a snapshot older than 30 seconds by one microsecond is stale" {
  export CPU_PROFILE_AUTO_TEST_TICKS=19 TEST_AGE=31 TEST_FRACTION=.999999
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "a stale or malformed sample clears the rolling window" {
  export CPU_PROFILE_AUTO_TEST_TICKS=31 TEST_BUSY=0 TEST_BUSY_CHANGE_AT=130 TEST_BUSY_CHANGE_TO=45 TEST_STALE_AT=130
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000300 performance' ]
  : > "$TEST_SETS"
  rm "$CPU_PROFILE_AUTO_STATE_DIR/state"
  printf 'Balanced\n' > "$TEST_PROFILE"
  unset TEST_STALE_AT
  export TEST_BAD_JSON_AT=130
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000300 performance' ]
}

@test "cooldown prevents a second switch until 300 seconds have passed" {
  export CPU_PROFILE_AUTO_TEST_TICKS=43 CPU_PROFILE_AUTO_DOWN_SECONDS=30
  export TEST_BUSY_CHANGE_AT=130 TEST_BUSY_CHANGE_TO=0
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = $'1800000120 performance\n1800000420 balanced' ]
}

@test "a manual choice holds for 1800 seconds from detection" {
  export CPU_PROFILE_AUTO_TEST_TICKS=199 TEST_PROFILE_CHANGE_AT=180 TEST_PROFILE_CHANGE_TO=Balanced
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = $'1800000120 performance\n1800001980 performance' ]
  [[ $output == *'manual profile change Performance -> Balanced; hold 1800s; busy 120s=45.00%'* ]]
}

@test "manual hold survives restarting the service" {
  export CPU_PROFILE_AUTO_TEST_TICKS=19 TEST_PROFILE_CHANGE_AT=180 TEST_PROFILE_CHANGE_TO=Balanced
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  export CPU_PROFILE_AUTO_TEST_START=1800000190 CPU_PROFILE_AUTO_TEST_TICKS=181
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = $'1800000120 performance\n1800001990 performance' ]
}

@test "a manual change while the service is stopped is detected on restart" {
  export CPU_PROFILE_AUTO_TEST_TICKS=13
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  printf 'Balanced\n' > "$TEST_PROFILE"
  export CPU_PROFILE_AUTO_TEST_START=1800000130 CPU_PROFILE_AUTO_TEST_TICKS=31
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000120 performance' ]
  [[ $output == *'manual profile change Performance -> Balanced; hold 1800s'* ]]
}

@test "the last switch cooldown survives a service restart" {
  export CPU_PROFILE_AUTO_TEST_TICKS=13 CPU_PROFILE_AUTO_DOWN_SECONDS=30
  export TEST_BUSY_CHANGE_AT=130 TEST_BUSY_CHANGE_TO=0
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  export CPU_PROFILE_AUTO_TEST_START=1800000130 CPU_PROFILE_AUTO_TEST_TICKS=31
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = $'1800000120 performance\n1800000430 balanced' ]
}

@test "timestamps with positive and negative timezone offsets are parsed" {
  export CPU_PROFILE_AUTO_TEST_TICKS=13 TEST_TIME_OFFSET=plus TEST_AGE=1 TEST_FRACTION=.123456
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000120 performance' ]
  : > "$TEST_SETS"
  rm "$CPU_PROFILE_AUTO_STATE_DIR/state"
  printf 'Balanced\n' > "$TEST_PROFILE"
  export TEST_TIME_OFFSET=minus
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000120 performance' ]
}

@test "the real clock loop reads the snapshot and waits 10 seconds" {
  unset CPU_PROFILE_AUTO_TEST_TICKS CPU_PROFILE_AUTO_TEST_HOOK
  export TEST_REAL_JQ
  TEST_REAL_JQ=$(command -v jq)
  printf '%s\n' "$(date +%s)" > "$TEST_CLOCK"
  printf '{"time":"%s","cpu":{"busy_percent":45}}\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%S.%6NZ')" > "$CPU_PROFILE_AUTO_SNAPSHOT"
  cat > "$WORK/bin/jq" <<'EOF'
#!/usr/bin/env bash
# Simulate a watcher write after the loop captured its clock, before jq reads.
printf '{"time":"%s","cpu":{"busy_percent":45}}\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%S.%6NZ')" > "$CPU_PROFILE_AUTO_SNAPSHOT"
"$TEST_REAL_JQ" "$@"
status=$?
printf '%s\n' "$status" > "$WORK/jq-status"
exit "$status"
EOF
  cat > "$WORK/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$WORK/sleep-argument"
exit 42
EOF
  chmod +x "$WORK/bin/jq" "$WORK/bin/sleep"
  run "$SCRIPT"
  [ "$status" -eq 42 ]
  [ "$(cat "$WORK/jq-status")" = 0 ]
  [ "$(cat "$WORK/sleep-argument")" = 10 ]
  [ "$(wc -l < "$TEST_READS")" -eq 1 ]
  [ ! -s "$TEST_SETS" ]
}

@test "future snapshots cannot trigger a switch" {
  export CPU_PROFILE_AUTO_TEST_TICKS=19 TEST_AGE=-1
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "thresholds and windows accept environment overrides" {
  export CPU_PROFILE_AUTO_TEST_TICKS=7 TEST_BUSY=35 CPU_PROFILE_AUTO_UP_PERCENT=34.50 CPU_PROFILE_AUTO_UP_SECONDS=60
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000060 performance' ]
}

@test "the down threshold and window accept environment overrides" {
  export CPU_PROFILE_AUTO_TEST_TICKS=7 TEST_BUSY=19 CPU_PROFILE_AUTO_DOWN_PERCENT=20 CPU_PROFILE_AUTO_DOWN_SECONDS=60
  printf 'Performance\n' > "$TEST_PROFILE"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000060 balanced' ]
}

@test "manual hold and cooldown accept environment overrides" {
  export CPU_PROFILE_AUTO_TEST_TICKS=31 TEST_PROFILE_CHANGE_AT=180 TEST_PROFILE_CHANGE_TO=Balanced
  export CPU_PROFILE_AUTO_COOLDOWN_SECONDS=60 CPU_PROFILE_AUTO_MANUAL_SECONDS=120
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = $'1800000120 performance\n1800000300 performance' ]
}

@test "a manual exit from Battery starts the hold" {
  export CPU_PROFILE_AUTO_TEST_TICKS=19 TEST_PROFILE_CHANGE_AT=60 TEST_PROFILE_CHANGE_TO=Balanced
  export CPU_PROFILE_AUTO_MANUAL_SECONDS=120
  printf 'Battery\n' > "$TEST_PROFILE"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000180 performance' ]
  [[ $output == *'manual profile change Battery -> Balanced; hold 120s'* ]]
}

@test "threshold comparisons use the unrounded mean" {
  export CPU_PROFILE_AUTO_TEST_TICKS=13 TEST_BUSY=39.99
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_SETS" ]
}

@test "profile reads happen no more than once a minute" {
  export CPU_PROFILE_AUTO_TEST_TICKS=19 TEST_BUSY=35
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_READS")" = $'1800000000\n1800000060\n1800000120\n1800000180' ]
}

@test "a failed set is rate limited and reported" {
  export CPU_PROFILE_AUTO_TEST_TICKS=43 TEST_SET_FAIL=1
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = $'1800000120 performance\n1800000420 performance' ]
  [[ $output == *'failed to switch to Performance'* ]]
}

@test "a set that applies the profile but exits non-zero is a switch, not a manual change" {
  export CPU_PROFILE_AUTO_TEST_TICKS=19 TEST_SET_PARTIAL=1
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000120 performance' ]
  [[ $output == *'switched to Performance'* ]]
  [[ $output != *'failed to switch'* ]]
  [[ $output != *'manual profile change'* ]]
  [ "$(cut -d' ' -f1,3 "$CPU_PROFILE_AUTO_STATE_DIR/state")" = 'Performance 0' ]
}

@test "only a failed switch pops a desktop notification; argos shows the rest" {
  export CPU_PROFILE_AUTO_TEST_TICKS=19 TEST_PROFILE_CHANGE_AT=180 TEST_PROFILE_CHANGE_TO=Balanced
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ $output == *'switched to Performance'*'manual profile change Performance -> Balanced'* ]]
  [ ! -s "$TEST_NOTES" ]
  rm "$CPU_PROFILE_AUTO_STATE_DIR/state"
  printf 'Balanced\n' > "$TEST_PROFILE"
  unset TEST_PROFILE_CHANGE_AT
  export CPU_PROFILE_AUTO_TEST_TICKS=13 TEST_SET_FAIL=1
  run "$SCRIPT"
  [[ $(cat "$TEST_NOTES") == *'CPU profile: switch to Performance failed'*'busy 120s=45.00%'* ]]
}

@test "a broken notifier never stops the switch loop" {
  export CPU_PROFILE_AUTO_TEST_TICKS=43 TEST_SET_FAIL=1 TEST_NOTIFY_FAIL=1
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = $'1800000120 performance\n1800000420 performance' ]
  [ -s "$TEST_NOTES" ]
}

@test "switches go through the power-profiles interface GNOME listens to" {
  export CPU_PROFILE_AUTO_TEST_TICKS=13
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_SETS")" = '1800000120 performance' ]
  [ "$(cat "$TEST_BUSCTL")" = '--system set-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile s performance' ]
}

@test "Balanced holds an 85 C thermal target from the first profile read" {
  export CPU_PROFILE_AUTO_TEST_TICKS=1 TEST_BUSY=10
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$CPU_PROFILE_AUTO_TCC_FILE")" = 20 ]
  [[ $output == *'thermal target 85C for Balanced'* ]]
}

@test "a switch to Performance restores the 92 C target and says so" {
  export CPU_PROFILE_AUTO_TEST_TICKS=13
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$CPU_PROFILE_AUTO_TCC_FILE")" = 13 ]
  [[ $output == *'thermal target 85C for Balanced'*'switched to Performance'*'thermal target 92C for Performance'* ]]
}

@test "a reset target is put back at the next profile read" {
  export CPU_PROFILE_AUTO_TEST_TICKS=7 TEST_BUSY=10
  cat >> "$CPU_PROFILE_AUTO_TEST_HOOK" <<'EOF'
cpu_profile_reset_hook() { (( $1 - TEST_EPOCH == 30 )) && printf '13\n' > "$CPU_PROFILE_AUTO_TCC_FILE"; return 0; }
eval "$(declare -f cpu_profile_test_before_tick | sed '2a cpu_profile_reset_hook "$1"')"
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$CPU_PROFILE_AUTO_TCC_FILE")" = 20 ]
  [ "$(grep -c 'thermal target 85C' <<< "$output")" -eq 2 ]
}

@test "Battery and unknown profiles leave the thermal target alone" {
  export CPU_PROFILE_AUTO_TEST_TICKS=7
  printf 'Battery\n' > "$TEST_PROFILE"
  run "$SCRIPT"
  [ "$(cat "$CPU_PROFILE_AUTO_TCC_FILE")" = 13 ]
}

@test "a refused target write is reported once and never stops the loop" {
  export CPU_PROFILE_AUTO_TEST_TICKS=19 TEST_SUDO_FAIL=1 TEST_BUSY=10
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$CPU_PROFILE_AUTO_TCC_FILE")" = 13 ]
  [ "$(grep -c 'failed to set thermal target' <<< "$output")" -eq 1 ]
}

@test "bad configuration and damaged state fail without changing a profile" {
  export CPU_PROFILE_AUTO_TEST_TICKS=1 CPU_PROFILE_AUTO_UP_PERCENT=101
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -s "$TEST_SETS" ]
  unset CPU_PROFILE_AUTO_UP_PERCENT
  mkdir -p "$CPU_PROFILE_AUTO_STATE_DIR"
  printf 'bad state\n' > "$CPU_PROFILE_AUTO_STATE_DIR/state"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -s "$TEST_SETS" ]
}
