#!/usr/bin/env bash
# Switch between Balanced and Performance using the resource watcher's cache.
set -eo pipefail

snapshot=${CPU_PROFILE_AUTO_SNAPSHOT:-"$HOME/.local/state/resource-watcher/current.json"}
power_supply_dir=${CPU_PROFILE_AUTO_POWER_SUPPLY_DIR:-/sys/class/power_supply}
state_dir=${CPU_PROFILE_AUTO_STATE_DIR:-${XDG_STATE_HOME:-"$HOME/.local/state"}/cpu-profile-auto}
state_file=${state_dir%/}/state
interval=10
profile_interval=60
snapshot_max_age=30

# Convert an unsigned decimal setting to a shell integer, rejecting overflow.
read_seconds() {
  local name=$1 value=$2
  if [[ ! $value =~ ^[0-9]{1,10}$ ]]; then
    printf 'invalid %s: %s\n' "$name" "$value" >&2
    exit 1
  fi
  printf -v "$name" '%d' "$((10#$value))"
}

# Convert a percentage with at most two decimal places to hundredths.
read_percent() {
  local name=$1 value=$2 whole fraction scaled
  if [[ ! $value =~ ^([0-9]{1,3})(\.([0-9]{1,2}))?$ ]]; then
    printf 'invalid %s: %s\n' "$name" "$value" >&2
    exit 1
  fi
  whole=${BASH_REMATCH[1]}
  fraction=${BASH_REMATCH[3]:-}
  fraction=${fraction}00
  fraction=${fraction:0:2}
  scaled=$((10#$whole * 100 + 10#$fraction))
  if (( scaled > 10000 )); then
    printf 'invalid %s: %s\n' "$name" "$value" >&2
    exit 1
  fi
  printf -v "$name" '%d' "$scaled"
}

up_seconds=0 down_seconds=0 cooldown_seconds=0 manual_seconds=0
up_threshold=0 down_threshold=0
read_seconds up_seconds "${CPU_PROFILE_AUTO_UP_SECONDS:-120}"
read_seconds down_seconds "${CPU_PROFILE_AUTO_DOWN_SECONDS:-300}"
read_seconds cooldown_seconds "${CPU_PROFILE_AUTO_COOLDOWN_SECONDS:-300}"
read_seconds manual_seconds "${CPU_PROFILE_AUTO_MANUAL_SECONDS:-1800}"
read_percent up_threshold "${CPU_PROFILE_AUTO_UP_PERCENT:-40}"
read_percent down_threshold "${CPU_PROFILE_AUTO_DOWN_PERCENT:-15}"
if (( up_seconds == 0 || down_seconds == 0 )); then
  printf 'load windows must be positive\n' >&2
  exit 1
fi
max_window=$up_seconds
(( down_seconds > max_window )) && max_window=$down_seconds

times=()
values=()
last_profile=none
last_switch=-1
manual_until=0
last_poll=-1
up_sum=0
up_count=0
down_sum=0
down_count=0
up_mean=unavailable
down_mean=unavailable

# Keep the cooldown and a detected manual choice through service restarts.
load_state() {
  local extra
  umask 077
  mkdir -p -- "$state_dir"
  [[ -e $state_file ]] || return 0
  if ! IFS=' ' read -r last_profile last_switch manual_until extra < "$state_file" ||
      [[ ! $last_profile =~ ^(none|Balanced|Performance|Battery)$ ]] ||
      [[ ! $last_switch =~ ^(-1|[0-9]+)$ ]] ||
      [[ ! $manual_until =~ ^[0-9]+$ ]] || [[ -n $extra ]]; then
    printf 'invalid cpu profile state: %s\n' "$state_file" >&2
    exit 1
  fi
}

# Replace the state atomically; it contains no load samples.
save_state() {
  printf '%s %s %s\n' "$last_profile" "$last_switch" "$manual_until" > "$state_file.tmp"
  mv -f -- "$state_file.tmp" "$state_file"
}

# Return busy percent in hundredths and the timestamp of a fresh snapshot.
read_snapshot() {
  local now_us=$1 test_clock=false
  [[ -n ${CPU_PROFILE_AUTO_TEST_TICKS:-} ]] && test_clock=true
  jq -er --argjson now_us "$now_us" --argjson test_clock "$test_clock" --argjson max_age "$snapshot_max_age" '
    try (
      (if $test_clock then $now_us else (now * 1000000 | floor) end) as $check_us
      |
      .cpu.busy_percent as $busy
      | .time
      | capture("^(?<stamp>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(?<fraction>\\.[0-9]+)?(?<zone>Z|[+-][0-9]{2}:[0-9]{2})$") as $t
      | ($t.stamp | strptime("%Y-%m-%dT%H:%M:%S") | mktime) as $base
      | (if $t.zone == "Z" then 0 else
           (($t.zone[1:3] | tonumber) * 3600 + ($t.zone[4:6] | tonumber) * 60)
           * (if $t.zone[0:1] == "-" then -1 else 1 end)
         end) as $offset
      | ((($t.fraction // ".")[1:] + "000000")[:6] | tonumber) as $fraction_us
      | (($base - $offset) * 1000000 + $fraction_us) as $timestamp_us
      | select(($busy | type) == "number" and $busy >= 0 and $busy <= 100)
      | select($timestamp_us <= $check_us and $check_us - $timestamp_us <= $max_age * 1000000)
      | "\(($busy * 100 | round)) \($timestamp_us)"
    ) catch empty
  ' "$snapshot" 2>/dev/null
}

# Match cpu-tcc-offset.service: unknown supply data is not barrel power.
barrel_power_online() {
  local supply kind online
  [[ -r $power_supply_dir/AC/online ]] || return 1
  IFS= read -r online < "$power_supply_dir/AC/online" || return 1
  [[ $online == 1 ]] || return 1
  for supply in "$power_supply_dir"/*; do
    [[ -r $supply/type ]] || return 1
    IFS= read -r kind < "$supply/type" || return 1
    [[ -n $kind ]] || return 1
    [[ $kind == USB ]] || continue
    [[ -r $supply/online ]] || return 1
    IFS= read -r online < "$supply/online" || return 1
    [[ $online == 0 ]] || return 1
  done
}

# Read the profile only at the minute boundary, including before a switch.
read_profile() {
  local output
  output=$(system76-power profile 2>/dev/null) || return 1
  case ${output%%$'\n'*} in
    'Power Profile: Balanced') profile=Balanced ;;
    'Power Profile: Performance') profile=Performance ;;
    'Power Profile: Battery') profile=Battery ;;
    *) return 1 ;;
  esac
}

# Calculate the arithmetic mean only after a complete window was observed.
window_mean() {
  local now_us=$1 window=$2 cutoff i
  cutoff=$((now_us - window * 1000000))
  mean_sum=0
  mean_count=0
  mean_display=unavailable
  (( ${#times[@]} > 0 && times[0] <= cutoff )) || return 0
  for ((i = 0; i < ${#times[@]}; i++)); do
    if (( times[i] >= cutoff )); then
      mean_sum=$((mean_sum + values[i]))
      mean_count=$((mean_count + 1))
    fi
  done
  if (( mean_count > 0 )); then
    local rounded=$(((mean_sum + mean_count / 2) / mean_count))
    printf -v mean_display '%d.%02d%%' "$((rounded / 100))" "$((rounded % 100))"
  fi
}

# Record one decision time before invoking the setter, even if it fails.
switch_profile() {
  local now_us=$1 target=$2
  last_switch=$now_us
  save_state
  if system76-power profile "${target,,}" >/dev/null; then
    if [[ -z ${CPU_PROFILE_AUTO_TEST_TICKS:-} ]]; then last_switch=${EPOCHREALTIME/.}; fi
    last_profile=$target
    save_state
    printf 'switched to %s; busy %ss=%s %ss=%s\n' "$target" "$up_seconds" "$up_mean" "$down_seconds" "$down_mean"
  else
    if [[ -z ${CPU_PROFILE_AUTO_TEST_TICKS:-} ]]; then last_switch=${EPOCHREALTIME/.}; fi
    save_state
    printf 'failed to switch to %s; busy %ss=%s %ss=%s\n' "$target" "$up_seconds" "$up_mean" "$down_seconds" "$down_mean" >&2
  fi
}

# Sample the cache, detect manual changes, and act only on a fresh profile read.
tick() {
  local now_us=$1 observed_us busy sample snapshot_us=-1 profile
  if sample=$(read_snapshot "$now_us"); then
    IFS=' ' read -r busy snapshot_us <<< "$sample"
    if (( ${#times[@]} > 0 )) &&
        (( now_us <= times[${#times[@]}-1] || now_us - times[${#times[@]}-1] > interval * 2000000 )); then
      times=()
      values=()
    fi
    times+=("$now_us")
    values+=("$busy")
    while (( ${#times[@]} > 1 && times[1] <= now_us - max_window * 1000000 )); do
      times=("${times[@]:1}")
      values=("${values[@]:1}")
    done
  else
    times=()
    values=()
  fi

  window_mean "$now_us" "$up_seconds"
  up_sum=$mean_sum up_count=$mean_count up_mean=$mean_display
  window_mean "$now_us" "$down_seconds"
  down_sum=$mean_sum down_count=$mean_count down_mean=$mean_display

  if (( last_poll >= 0 && now_us >= last_poll && now_us - last_poll < profile_interval * 1000000 )); then
    return 0
  fi
  last_poll=$now_us
  read_profile || return 0
  observed_us=$now_us
  if [[ -z ${CPU_PROFILE_AUTO_TEST_TICKS:-} ]]; then observed_us=${EPOCHREALTIME/.}; fi
  if (( snapshot_us < 0 || observed_us < snapshot_us ||
        observed_us - snapshot_us > snapshot_max_age * 1000000 ||
        observed_us - now_us > interval * 2000000 )); then
    times=() values=()
    up_count=0 down_count=0 up_mean=unavailable down_mean=unavailable
  fi
  if [[ $last_profile != none && $profile != "$last_profile" ]]; then
    manual_until=$((observed_us + manual_seconds * 1000000))
    printf 'manual profile change %s -> %s; hold %ss; busy %ss=%s %ss=%s\n' \
      "$last_profile" "$profile" "$manual_seconds" "$up_seconds" "$up_mean" "$down_seconds" "$down_mean"
    last_profile=$profile
    save_state
  elif [[ $last_profile == none ]]; then
    last_profile=$profile
    save_state
  fi

  (( ${#times[@]} > 0 && observed_us >= manual_until )) || return 0
  (( last_switch < 0 || observed_us - last_switch >= cooldown_seconds * 1000000 )) || return 0
  case $profile in
    Balanced)
      (( up_count > 0 && up_sum >= up_threshold * up_count )) || return 0
      barrel_power_online && switch_profile "$observed_us" Performance
      ;;
    Performance)
      (( down_count > 0 && down_sum <= down_threshold * down_count )) || return 0
      barrel_power_online && switch_profile "$observed_us" Balanced
      ;;
  esac
  return 0
}

# The test mode advances a fake clock and can update fixtures before each tick.
main() {
  local now tick_number=0 test_ticks=${CPU_PROFILE_AUTO_TEST_TICKS:-}
  load_state
  if [[ -n $test_ticks ]]; then
    read_seconds test_ticks "$test_ticks"
    read_seconds now "${CPU_PROFILE_AUTO_TEST_START:-}"
    if [[ -n ${CPU_PROFILE_AUTO_TEST_HOOK:-} ]]; then
      # shellcheck source=/dev/null
      source "$CPU_PROFILE_AUTO_TEST_HOOK"
    fi
    while (( tick_number < test_ticks )); do
      if [[ -n ${CPU_PROFILE_AUTO_TEST_HOOK:-} ]]; then
        cpu_profile_test_before_tick "$now" "$tick_number"
      fi
      tick "$((now * 1000000))"
      tick_number=$((tick_number + 1))
      now=$((now + interval))
    done
  else
    while true; do
      now=${EPOCHREALTIME/.}
      tick "$now"
      sleep "$interval"
    done
  fi
}

main "$@"
