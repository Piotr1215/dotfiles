#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

make_picker_stubs() {
  stub_bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_bin"

  cat >"$stub_bin/zoxide" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$CODEX_TEST_REPO_ONE" "$CODEX_TEST_REPO_TWO"
EOF
  cat >"$stub_bin/fzf" <<'EOF'
#!/usr/bin/env bash
input=$(cat)
grep -Fxq "$CODEX_TEST_REPO_ONE" <<< "$input" || exit 90
grep -Fxq "$CODEX_TEST_REPO_TWO" <<< "$input" || exit 91
printf '%s\n%s\n' "${CODEX_TEST_KEY:-}" "$CODEX_TEST_SELECTION"
EOF
  chmod +x "$stub_bin/zoxide" "$stub_bin/fzf"
}

@test "Codex launcher opens a repository picker and starts in the selection" {
  make_picker_stubs
  repo_one="$BATS_TEST_TMPDIR/repo-one"
  repo_two="$BATS_TEST_TMPDIR/repo-two"
  mkdir -p "$repo_one" "$repo_two"

  run env PATH="$stub_bin:$PATH" CODEX_LAUNCH_DRY_RUN=1 \
    CODEX_TEST_REPO_ONE="$repo_one" CODEX_TEST_REPO_TWO="$repo_two" \
    CODEX_TEST_SELECTION="$repo_two" "$repo_root/scripts/__codex_launcher.sh"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.action' <<<"$output")" = "new" ]
  [ "$(jq -r '.cwd' <<<"$output")" = "$repo_two" ]
}

@test "Codex repository picker keeps resume actions" {
  make_picker_stubs
  repo_one="$BATS_TEST_TMPDIR/repo-one"
  repo_two="$BATS_TEST_TMPDIR/repo-two"
  mkdir -p "$repo_one" "$repo_two"

  run env PATH="$stub_bin:$PATH" CODEX_LAUNCH_DRY_RUN=1 \
    CODEX_TEST_REPO_ONE="$repo_one" CODEX_TEST_REPO_TWO="$repo_two" \
    CODEX_TEST_SELECTION="$repo_one" CODEX_TEST_KEY=ctrl-r \
    "$repo_root/scripts/__codex_launcher.sh"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.action' <<<"$output")" = "resume" ]
  [ "$(jq -r '.cwd' <<<"$output")" = "$repo_one" ]
}

@test "Codex launcher routes Loft repositories to the work account" {
  run env CODEX_LAUNCH_DRY_RUN=1 "$repo_root/scripts/__codex_launcher.sh" \
    --cwd /home/decoder/loft/loft-router resume

  [ "$status" -eq 0 ]
  [ "$(jq -r '.action' <<<"$output")" = "resume" ]
  [ "$(jq -r '.codex_home' <<<"$output")" = "/home/decoder/.codex-work" ]
}

@test "Codex launcher routes personal repositories to the personal account" {
  run env CODEX_LAUNCH_DRY_RUN=1 "$repo_root/scripts/__codex_launcher.sh" \
    --cwd /home/decoder/dev/dotfiles new

  [ "$status" -eq 0 ]
  [ "$(jq -r '.action' <<<"$output")" = "new" ]
  [ "$(jq -r '.codex_home' <<<"$output")" = "/home/decoder/.codex" ]
}

@test "Codex launcher ignores an unresolved tmux cwd format" {
  run env CODEX_LAUNCH_DRY_RUN=1 CODEX_LAUNCH_CWD=/home/decoder/loft/loft-router \
    "$repo_root/scripts/__codex_launcher.sh" --cwd '#{pane_current_path}' new

  [ "$status" -eq 0 ]
  [ "$(jq -r '.cwd' <<<"$output")" = "/home/decoder/loft/loft-router" ]
  [ "$(jq -r '.codex_home' <<<"$output")" = "/home/decoder/.codex-work" ]
}

@test "Codex launcher uses the canonical wrapper from Codex home" {
  fixture_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$fixture_home/.codex/scripts"
  cat >"$fixture_home/.codex/scripts/__codex_with_app_server.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$0"
EOF
  chmod +x "$fixture_home/.codex/scripts/__codex_with_app_server.sh"

  run env HOME="$fixture_home" CODEX_LAUNCH_CWD=/tmp \
    "$repo_root/scripts/__codex_launcher.sh" new

  [ "$status" -eq 0 ]
  [ "$output" = "$fixture_home/.codex/scripts/__codex_with_app_server.sh" ]
}
