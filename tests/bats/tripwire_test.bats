#!/usr/bin/env bats

# __tripwire.sh watches a news search and acts when Jev says a new headline
# meets a wire's condition. These tests stub the feed (curl), the judge
# (Jev, through TRIPWIRE_JEV) and every action, and check when a wire arms, trips, stays quiet
# and fails loud. yq and jq run for real.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__tripwire.sh"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config" XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export TRIPWIRE_JEV="${BATS_TEST_TMPDIR}/bin/jev" TRIPWIRE_SND="${BATS_TEST_TMPDIR}/snd.js"
  export FEED="${BATS_TEST_TMPDIR}/feed.xml" LOG="${BATS_TEST_TMPDIR}/log"
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/classif"
  : >"$LOG"
  stub curl '[[ -n "$FEED_FAIL" ]] && exit 22; cat "$FEED"'
  # A headline holding "squeeze" scores 0.95, any other 0.05; JEV_P forces a score; JEV_FAIL makes the judge unscored.
  stub jev 'echo "jev $*" >>"$LOG"; [[ -n "$JEV_FAIL" ]] && exit 1; [[ -n "$JEV_P" ]] && { echo "$JEV_P"; exit 0; }; grep -q squeeze && { echo 0.95; exit 0; }; echo 0.05'
  stub notify-send 'echo "notify $*" >>"$LOG"'
  stub node 'echo "node $*" >>"$LOG"'
  export PATH="${BATS_TEST_TMPDIR}/bin:$PATH"
}

stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"${BATS_TEST_TMPDIR}/bin/$1"
  chmod +x "${BATS_TEST_TMPDIR}/bin/$1"
}

# The feed holds these headlines, each "id:title".
feed() {
  {
    printf '<?xml version="1.0"?><rss version="2.0"><channel><title>t</title>'
    local h
    for h in "$@"; do
      printf '<item><title>%s</title><link>https://x/%s</link><guid isPermaLink="false">%s</guid><pubDate>Sat, 03 Oct 2026 10:00:00 GMT</pubDate></item>' \
        "${h#*:}" "${h%%:*}" "${h%%:*}"
    done
    printf '</channel></rss>'
  } >"$FEED"
}

add_wire() {
  "$SCRIPT" add vmware "VMware Broadcom" "Does Broadcom squeeze partners?" "${1:-notify}" >/dev/null
}

@test "add, list and rm manage a wire file" {
  run "$SCRIPT" add vmware "VMware Broadcom" "Does Broadcom squeeze partners?"
  [ "$status" -eq 0 ]
  grep -qx 'query=VMware Broadcom' "$XDG_CONFIG_HOME/tripwire/wires/vmware"
  run "$SCRIPT" list
  [[ "$output" == *"vmware"*"VMware Broadcom"*"notify"*"arms on its next run"* ]]
  run "$SCRIPT" add vmware "x" "y"
  [ "$status" -eq 2 ]
  run "$SCRIPT" rm vmware
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/tripwire/wires/vmware" ]
}

@test "the first run arms the wire: old headlines are recorded and nothing is judged" {
  add_wire
  feed "a1:Broadcom will squeeze partners" "a2:VMware ships a release"
  run "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$XDG_STATE_HOME/tripwire/vmware.seen")" -eq 2 ]
  ! grep -q '^jev\|^notify' "$LOG"
}

@test "a feed of one headline arms on that headline, and an empty feed arms on none" {
  add_wire
  feed "a1:old"
  "$SCRIPT" run
  [ "$(cat "$XDG_STATE_HOME/tripwire/vmware.seen")" = a1 ]
  "$SCRIPT" rm vmware >/dev/null && add_wire
  feed
  "$SCRIPT" run
  [ ! -s "$XDG_STATE_HOME/tripwire/vmware.seen" ]
}

@test "a new headline meeting the condition trips once; one that does not stays quiet" {
  add_wire
  feed "a1:old news"
  "$SCRIPT" run
  feed "a1:old news" "b2:Broadcom moves to squeeze partners" "c3:VMware ships a release"
  run "$SCRIPT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Broadcom moves to squeeze partners"* ]]
  [ "$(grep -c '^notify' "$LOG")" -eq 1 ]
  grep -q '^notify tripwire: vmware Broadcom moves to squeeze partners' "$LOG"
  [ "$(grep -c '^jev' "$LOG")" -eq 2 ]
  run "$SCRIPT" run
  [ "$(grep -c '^jev' "$LOG")" -eq 2 ]
}

@test "the judge asks Jev the condition about the headline" {
  add_wire
  feed "a1:old"
  "$SCRIPT" run
  feed "a1:old" "b2:Broadcom squeeze"
  "$SCRIPT" run
  grep -q '^jev Does Broadcom squeeze partners?$' "$LOG"
}

@test "an unscored headline stays unseen and the wire fails loud once, then says when it recovers" {
  add_wire
  feed "a1:old"
  "$SCRIPT" run
  feed "a1:old" "b2:Broadcom squeeze"
  JEV_FAIL=1 run "$SCRIPT" run
  [ "$status" -eq 1 ]
  ! grep -qx b2 "$XDG_STATE_HOME/tripwire/vmware.seen"
  [ "$(grep -c 'is broken' "$LOG")" -eq 1 ]
  JEV_FAIL=1 run "$SCRIPT" run
  [ "$(grep -c 'is broken' "$LOG")" -eq 1 ]
  run "$SCRIPT" run
  [ "$status" -eq 0 ]
  grep -q 'works again' "$LOG"
  grep -q '^notify tripwire: vmware Broadcom squeeze' "$LOG"
}

@test "a feed that does not answer fails loud" {
  add_wire
  FEED_FAIL=1 run "$SCRIPT" run
  [ "$status" -eq 1 ]
  grep -q 'is broken: the news feed did not answer' "$LOG"
  run "$SCRIPT" list
  [[ "$output" == *"broken: the news feed did not answer"* ]]
}

@test "with CLASSIF=0 nothing is fetched or judged" {
  add_wire
  feed "a1:old"
  stub curl 'echo "curl $*" >>"$LOG"'
  CLASSIF=0 run "$SCRIPT" run
  [ "$status" -eq 0 ]
  [ ! -s "$LOG" ]
}

@test "a dm action sends the trip to an agent on the bus" {
  add_wire "dm gordon"
  feed "a1:old"
  "$SCRIPT" run
  feed "a1:old" "b2:Broadcom squeeze"
  "$SCRIPT" run
  grep -q "^node $TRIPWIRE_SND -t gordon tripwire vmware: Broadcom squeeze https://x/b2" "$LOG"
}

@test "a command action gets the trip in TRIP_ variables" {
  add_wire 'echo "cmd $TRIP_WIRE|$TRIP_TITLE|$TRIP_LINK" >>"$LOG"'
  feed "a1:old"
  "$SCRIPT" run
  feed "a1:old" "b2:Broadcom squeeze"
  "$SCRIPT" run
  grep -qx 'cmd vmware|Broadcom squeeze|https://x/b2' "$LOG"
}

@test "test judges the current headlines and keeps no state" {
  feed "a1:Broadcom squeeze" "b2:VMware ships a release"
  run "$SCRIPT" test "VMware Broadcom" "Does Broadcom squeeze partners?"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Broadcom squeeze"* ]]
  [[ "$output" != *"ships a release"* ]]
  [ ! -d "$XDG_STATE_HOME/tripwire" ]
}

@test "only a yes at p 0.8 or more trips: 0.79 stays quiet, 0.80 trips" {
  add_wire
  feed "a1:old"
  "$SCRIPT" run
  feed "a1:old" "b2:Broadcom squeeze"
  JEV_P=0.79 run "$SCRIPT" run
  [ "$status" -eq 0 ]
  ! grep -q '^notify' "$LOG"
  feed "a1:old" "b2:Broadcom squeeze" "c3:Broadcom squeeze again"
  JEV_P=0.80 run "$SCRIPT" run
  [ "$(grep -c '^notify tripwire: vmware' "$LOG")" -eq 1 ]
}

@test "an answer that is not a number counts as unscored" {
  add_wire
  feed "a1:old"
  "$SCRIPT" run
  feed "a1:old" "b2:Broadcom squeeze"
  JEV_P="no answer" run "$SCRIPT" run
  [ "$status" -eq 1 ]
  grep -q 'jev could not judge' "$LOG"
}
