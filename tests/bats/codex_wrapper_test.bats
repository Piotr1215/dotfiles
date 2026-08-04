#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  fixture_root="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$fixture_root/bin" "$fixture_root/config"

  cat > "$fixture_root/bin/direnv" <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2" == "export bash" ]] || exit 1
printf 'export CODEX_DIRENV_PROBE=loaded\n'
EOF
  chmod +x "$fixture_root/bin/direnv"

  cat > "$fixture_root/bin/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\t%s\n' \
  "${CODEX_DIRENV_PROBE:-missing}" \
  "${CODEX_HOME:-personal}" \
  "${BROWSER:-missing}"
EOF
  chmod +x "$fixture_root/bin/codex"
}

@test "Codex wrapper evaluates direnv before launching the CLI" {
  run env PATH="$fixture_root/bin:$PATH" \
    CODEX_BIN="$fixture_root/bin/codex" \
    CODEX_CONFIG_ROOT="$fixture_root/config" \
    "$repo_root/scripts/__codex_with_app_server.sh" mcp list

  [ "$status" -eq 0 ]
  [ "${output%%$'\t'*}" = "loaded" ]
}

@test "Codex wrapper routes a Loft cwd to the work account and browser" {
  cd /home/decoder/loft/loft-router

  run env PATH="$fixture_root/bin:$PATH" \
    CODEX_HOME="$fixture_root/wrong-account" \
    CODEX_BIN="$fixture_root/bin/codex" \
    CODEX_CONFIG_ROOT="$fixture_root/config" \
    "$repo_root/scripts/__codex_with_app_server.sh" mcp list

  [ "$status" -eq 0 ]
  [ "$output" = $'loaded\t/home/decoder/.codex-work\tgoogle-chrome' ]
}

@test "Codex wrapper routes a personal cwd to the personal account and browser" {
  cd /home/decoder/dev/dotfiles

  run env PATH="$fixture_root/bin:$PATH" \
    CODEX_HOME="$fixture_root/wrong-account" \
    CODEX_BIN="$fixture_root/bin/codex" \
    CODEX_CONFIG_ROOT="$fixture_root/config" \
    "$repo_root/scripts/__codex_with_app_server.sh" mcp list

  [ "$status" -eq 0 ]
  [ "$output" = $'loaded\tpersonal\tlibrewolf' ]
}
