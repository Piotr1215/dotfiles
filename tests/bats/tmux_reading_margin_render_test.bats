#!/usr/bin/env bats

setup() {
  work="${BATS_TEST_DIRNAME}/../../scripts/__tmux_reading_margin_work.sh"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/cache"
  cat >"$BATS_TEST_TMPDIR/bin/tmux" <<'SCRIPT'
#!/usr/bin/env bash
cat "$WIDTH_FILE"
SCRIPT
  cat >"$BATS_TEST_TMPDIR/bin/cockpit" <<'SCRIPT'
#!/usr/bin/env bash
sleep 0.6
printf 'width=%s cache=%s\n' "$COCKPIT_VERTICAL_WIDTH" "${COCKPIT_CACHE:-1}"
printf 'AGENT: live-worker\n'
SCRIPT
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux" "$BATS_TEST_TMPDIR/bin/cockpit"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" WIDTH_FILE="$BATS_TEST_TMPDIR/width"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/cache" TMUX_PANE='%99' TMUX='test-server,1,0'
  export TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND="$BATS_TEST_TMPDIR/bin/cockpit"
  export TMUX_READING_MARGIN_FOCUS_COMMAND="$BATS_TEST_TMPDIR/absent"
}

@test "first draw renders synchronously at the pane width without a loading placeholder" {
  printf '35\n' >"$WIDTH_FILE"
  run "$work" --cached-render test '@1'
  [ "$status" -eq 0 ]
  [[ "$output" == *'AGENT: live-worker'* ]]
  [[ "$output" == *'width=35 cache=0'* ]]
  [[ "$output" != *'Loading'* ]]
}

@test "each draw uses the current width including narrow panes" {
  printf '35\n' >"$WIDTH_FILE"
  run "$work" --cached-render test '@1'
  [ "$status" -eq 0 ]
  printf '52\n' >"$WIDTH_FILE"
  run timeout 1 "$work" --cached-render test '@1'
  [ "$status" -eq 0 ]
  [[ "$output" == *'width=52 cache=0'* ]]
  printf '12\n' >"$WIDTH_FILE"
  run timeout 1 "$work" --cached-render test '@1'
  [ "$status" -eq 0 ]
  [[ "$output" == *'width=12 cache=0'* ]]
  printf '1\n' >"$WIDTH_FILE"
  run timeout 1 "$work" --cached-render test '@1'
  [ "$status" -eq 0 ]
  [[ "$output" == *'width=1 cache=0'* ]]
}

@test "focus is cached at each width and redrawn when the width changes" {
  focus="$BATS_TEST_TMPDIR/bin/focus"
  cat >"$focus" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FOCUS_CALLS"
printf 'focus at %s\n' "$3"
SCRIPT
  chmod +x "$focus"
  export TMUX_READING_MARGIN_FOCUS_COMMAND="$focus" FOCUS_CALLS="$BATS_TEST_TMPDIR/focus-calls"
  printf '35\n' >"$WIDTH_FILE"
  run "$work" --cached-render test '@1'
  [[ "$output" == *'focus at 35'* ]]
  run "$work" --cached-render test '@1'
  [ "$(wc -l <"$FOCUS_CALLS")" -eq 1 ]
  printf '52\n' >"$WIDTH_FILE"
  run "$work" --cached-render test '@1'
  [[ "$output" == *'focus at 52'* ]]
  [ "$(wc -l <"$FOCUS_CALLS")" -eq 2 ]
}
