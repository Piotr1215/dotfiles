#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
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
