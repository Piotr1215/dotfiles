#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$HOME/dev/dotfiles/scripts" "$BATS_TEST_TMPDIR/bin"
  LOOPBACK="$BATS_TEST_DIRNAME/../../scripts/__notion_loopback.sh"
  WIDGET="$BATS_TEST_DIRNAME/../../.config/argos/notion-mic.1s.sh"
  cat > "$BATS_TEST_TMPDIR/bin/pactl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
  'list short sinks') [ "${FAIL_SINKS:-0}" = 0 ] || exit "$FAIL_SINKS"; printf '%s\n' "${SINKS:-}" ;;
  'list short sources') [ "${FAIL_SOURCES:-0}" = 0 ] || exit "$FAIL_SOURCES"; printf '%s\n' "${SOURCES:-}" ;;
  *) exit 1 ;;
esac
STUB
  printf '#!/usr/bin/env bash\nexit 3\n' > "$BATS_TEST_TMPDIR/bin/systemctl"
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
}

@test "status reports the active snapshot with one query per list" {
  export SINKS=$'1\tother\tdriver\n42\tnotion_capture\tdriver'
  export SOURCES=$'19\tnotion_mic\tdriver\n18\tnotion_capture.monitor\tdriver'
  run bash "$LOOPBACK" status
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'notion_loopback: UP\n  sink   #42 notion_capture\n  source #18 notion_capture.monitor\n  remap  #19 notion_mic (pick this in Notion)')" ]
  [ "$(cat "$CALLS")" = "$(printf 'list short sinks\nlist short sources')" ]
}

@test "status reports down without querying sources for a partial name" {
  export SINKS=$'42\tnotion_capture_extra\tdriver'
  run bash "$LOOPBACK" status
  [ "$status" -eq 1 ]
  [ "$output" = 'notion_loopback: DOWN' ]
  [ "$(cat "$CALLS")" = 'list short sinks' ]
}

@test "sink query failure reports down" {
  export FAIL_SINKS=7
  run bash "$LOOPBACK" status
  [ "$status" -eq 1 ]
  [ "$output" = 'notion_loopback: DOWN' ]
  [ "$(cat "$CALLS")" = 'list short sinks' ]
}

@test "source query failure retains the error and the sink already reported" {
  export SINKS=$'42\tnotion_capture\tdriver' FAIL_SOURCES=7
  run bash "$LOOPBACK" status
  [ "$status" -eq 7 ]
  [ "$output" = "$(printf 'notion_loopback: UP\n  sink   #42 notion_capture')" ]
  [ "$(cat "$CALLS")" = "$(printf 'list short sinks\nlist short sources')" ]
}

@test "a successful empty source list still reports up" {
  export SINKS=$'42\tnotion_capture\tdriver'
  run bash "$LOOPBACK" status
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'notion_loopback: UP\n  sink   #42 notion_capture')" ]
}

@test "widget uses one status snapshot for its menu" {
  cat > "$HOME/dev/dotfiles/scripts/__notion_loopback.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
printf 'notion_loopback: UP\n  sink   #42 notion_capture\n'
STUB
  chmod +x "$HOME/dev/dotfiles/scripts/__notion_loopback.sh"
  run bash "$WIDGET"
  [ "$status" -eq 0 ]
  [ "$(cat "$CALLS")" = status ]
  [[ "$output" == *'  sink   #42 notion_capture | font=monospace'* ]]
}
