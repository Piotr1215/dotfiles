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
  show-options) [[ ! -f "$HOOK_MARKER.${@: -1}" ]] || cat "$HOOK_MARKER.${@: -1}" ;;
  set-hook) printf '%s\n' "$*" >>"$HOOK_LOG" ;;
  set-option) printf '%s\n' "${@: -1}" >"$HOOK_MARKER.${@: -2:1}" ;;
esac
SCRIPT
  cat >"$BATS_TEST_TMPDIR/bin/python3" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${2:-}" == --state-dir ]]; then printf '%s\n' "$SHARED_STATE"; exit 0; fi
[[ -x "$TMUX_READING_MARGIN_COLLECT_COMMAND" ]] || exit 1
printf '%s\n' "$* window=$TMUX_READING_MARGIN_WINDOW" >>"$VIEWER_LOG"
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
  [ "$(wc -l <"$HOOK_LOG")" -eq 10 ]
  [ "$(wc -l <"$VIEWER_LOG")" -eq 2 ]
  [[ $(cat "$HOOK_LOG") == *'set-hook -ag after-set-option'* ]]
  [[ $(cat "$HOOK_LOG") == *"$SHARED_STATE/dirty"* ]]
  [[ $(cat "$VIEWER_LOG") == *'--raw-render other @2'* ]]
  [[ $(cat "$VIEWER_LOG") == *'window=@2'* ]]
  focus_hook=$(rg 'set-hook -ag window-pane-changed ' "$HOOK_LOG")
  [[ "$focus_hook" == *'window-pane-changed run-shell -b '* ]]
  [[ "$focus_hook" == *'active-'* ]]
  [[ "$focus_hook" != *'/dirty'* ]]
}

@test "raw collection shows the roster without the retired handoff panel" {
  run "$work" --raw-render test '@1'
  [ "$status" -eq 0 ]
  [[ "$output" == *'AGENT: live-worker'* ]]
  [[ "$output" != *'HANDOFFS'* ]]
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

