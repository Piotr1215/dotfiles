#!/usr/bin/env bats

# geoclue on this laptop cannot resolve a location (its only backend is
# Mozilla's dead service), so the timezone follows the public IP through a
# NetworkManager dispatcher script instead. These tests stub every external
# command and check what the script sets, and when it refuses to.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__auto_timezone.sh"
  ZONEINFO="${BATS_TEST_TMPDIR}/zoneinfo"
  mkdir -p "$ZONEINFO/Europe"
  touch "$ZONEINFO/Europe/Athens" "$ZONEINFO/Europe/Berlin"
  LOG="${BATS_TEST_TMPDIR}/log"
  : >"$LOG"
}

# Run the script with curl, nmcli, tailscale, timedatectl and logger stubbed.
# $1 lookup reply, $2 current zone, $3 nmcli active list, $4 tailscale json,
# then the dispatcher args.
tz() {
  local reply="$1" current="$2" nm="$3" ts="$4"; shift 4
  REPLY="$reply" CURRENT="$current" NM="$nm" TS="$ts" LOG="$LOG" \
  AUTO_TIMEZONE_ZONEINFO="$ZONEINFO" AUTO_TIMEZONE_URL="stub://" bash -c '
    curl() { [[ "$REPLY" == FAIL ]] && return 22; printf "%s\n" "$REPLY"; }
    nmcli() { printf "%b" "$NM"; }
    tailscale() { printf "%s\n" "$TS"; }
    timedatectl() {
      case "$1" in
        show) printf "%s\n" "$CURRENT" ;;
        set-timezone) printf "set %s\n" "$2" >>"$LOG" ;;
      esac
    }
    logger() { shift 2; printf "log %s\n" "$*" >>"$LOG"; }
    export -f curl nmcli tailscale timedatectl logger
    "'"$SCRIPT"'" "$@"
  ' _ "$@"
}

@test "sets the zone when the lookup differs from the current one" {
  run tz "Europe/Athens" "Europe/Berlin" "" '{"ExitNodeStatus": null}' wlan0 up
  [ "$status" -eq 0 ]
  grep -q '^set Europe/Athens$' "$LOG"
  grep -q 'Europe/Berlin -> Europe/Athens' "$LOG"
}

@test "does nothing when the zone already matches" {
  run tz "Europe/Athens" "Europe/Athens" "" '{"ExitNodeStatus": null}' wlan0 up
  [ "$status" -eq 0 ]
  ! grep -q '^set' "$LOG"
}

@test "runs by hand with no arguments" {
  run tz "Europe/Athens" "Europe/Berlin" "" '{"ExitNodeStatus": null}'
  [ "$status" -eq 0 ]
  grep -q '^set Europe/Athens$' "$LOG"
}

@test "ignores dispatcher actions other than up and connectivity-change" {
  run tz "Europe/Athens" "Europe/Berlin" "" '{"ExitNodeStatus": null}' wlan0 down
  [ "$status" -eq 0 ]
  [ ! -s "$LOG" ]
}

@test "leaves the zone alone behind a NetworkManager vpn" {
  run tz "Europe/Athens" "Europe/Berlin" "wireguard:activated\n802-11-wireless:activated\n" '{"ExitNodeStatus": null}' wlan0 up
  [ "$status" -eq 0 ]
  ! grep -q '^set' "$LOG"
  grep -q 'vpn or exit node active' "$LOG"
}

@test "leaves the zone alone behind a tailscale exit node" {
  run tz "Europe/Athens" "Europe/Berlin" "" '{"ExitNodeStatus": {"ID": "n1", "Online": true}}' wlan0 up
  [ "$status" -eq 0 ]
  ! grep -q '^set' "$LOG"
}

@test "refuses a zone that is not in zoneinfo" {
  run tz "Mars/Olympus" "Europe/Berlin" "" '{"ExitNodeStatus": null}' wlan0 up
  [ "$status" -eq 0 ]
  ! grep -q '^set' "$LOG"
  grep -q 'no usable zone' "$LOG"
}

@test "refuses a reply that is not a zone name" {
  run tz "<html>blocked</html>" "Europe/Berlin" "" '{"ExitNodeStatus": null}' wlan0 up
  [ "$status" -eq 0 ]
  ! grep -q '^set' "$LOG"
}

@test "a failed lookup logs and leaves the zone" {
  run tz FAIL "Europe/Berlin" "" '{"ExitNodeStatus": null}' wlan0 up
  [ "$status" -eq 0 ]
  ! grep -q '^set' "$LOG"
  grep -q 'lookup failed' "$LOG"
}
