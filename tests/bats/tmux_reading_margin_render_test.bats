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

@test "startup builds once and appends invalidation hooks once per server" {
  export SHARED_STATE="$BATS_TEST_TMPDIR/shared" HOOK_LOG="$BATS_TEST_TMPDIR/hooks"
  export HOOK_MARKER="$BATS_TEST_TMPDIR/hook-marker" BUILD_LOG="$BATS_TEST_TMPDIR/builds"
  export VIEWER_LOG="$BATS_TEST_TMPDIR/viewer"
  unset TMUX_READING_MARGIN_COLLECT_COMMAND
  cat >"$BATS_TEST_TMPDIR/bin/tmux" <<'SCRIPT'
#!/usr/bin/env bash
case "$1" in
  show-options) [[ ! -f "$HOOK_MARKER" ]] || cat "$HOOK_MARKER" ;;
  set-hook) printf '%s\n' "$*" >>"$HOOK_LOG" ;;
  set-option) printf '%s\n' "${@: -1}" >"$HOOK_MARKER" ;;
esac
SCRIPT
  cat >"$BATS_TEST_TMPDIR/bin/python3" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${2:-}" == --state-dir ]]; then printf '%s\n' "$SHARED_STATE"; exit 0; fi
[[ -x "$TMUX_READING_MARGIN_COLLECT_COMMAND" ]] || exit 1
printf '%s\n' "$*" >>"$VIEWER_LOG"
SCRIPT
  cat >"$BATS_TEST_TMPDIR/bin/go" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BUILD_LOG"
while (($#)); do
  if [[ "$1" == -o ]]; then printf '#!/bin/sh\nexit 0\n' >"$2"; chmod +x "$2"; exit 0; fi
  shift
done
exit 1
SCRIPT
  chmod +x "$BATS_TEST_TMPDIR/bin/"{tmux,python3,go}
  run "$work" test '@1'
  [ "$status" -eq 0 ]
  run "$work" other '@2'
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BUILD_LOG")" -eq 1 ]
  [ "$(wc -l <"$HOOK_LOG")" -eq 9 ]
  [ "$(wc -l <"$VIEWER_LOG")" -eq 2 ]
  [[ $(cat "$HOOK_LOG") == *'set-hook -ag after-set-option'* ]]
  [[ $(cat "$HOOK_LOG") == *"$SHARED_STATE/dirty"* ]]
  [[ $(cat "$VIEWER_LOG") == *'--raw-render other @2'* ]]
}

@test "shared raw collection reads handoffs fresh on every input change" {
  focus="$BATS_TEST_TMPDIR/bin/focus"
  cat >"$focus" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FOCUS_CALLS"
cat "$FOCUS_VALUE"
SCRIPT
  chmod +x "$focus"
  export TMUX_READING_MARGIN_FOCUS_COMMAND="$focus" FOCUS_CALLS="$BATS_TEST_TMPDIR/focus-calls"
  export FOCUS_VALUE="$BATS_TEST_TMPDIR/focus-value"
  printf 'first handoff\n' >"$FOCUS_VALUE"
  run "$work" --raw-render test '@1'
  [ "$status" -eq 0 ]
  [[ "$output" == *'first handoff'* ]]
  printf 'changed handoff\n' >"$FOCUS_VALUE"
  run "$work" --raw-render other '@2'
  [ "$status" -eq 0 ]
  [[ "$output" == *'changed handoff'* ]]
  [ "$(wc -l <"$FOCUS_CALLS")" -eq 2 ]
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
