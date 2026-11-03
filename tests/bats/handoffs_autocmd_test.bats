#!/usr/bin/env bats
# The nvim BufWritePost autocmd for a per-handoff file runs
# `__handoffs_file.py save <path>` and ignores other files.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/scripts" "$HOME/.local/state/gordon"
  cat > "$HOME/.claude/scripts/__handoffs_file.py" <<'S'
#!/usr/bin/env bash
echo "$*" >> "$BATS_TEST_TMPDIR/save.calls"
echo "sent: 0341: stub"
S
  chmod +x "$HOME/.claude/scripts/__handoffs_file.py"
  # Only the handoffs block of autocommands.lua, so no plugin is needed.
  { echo 'local api = vim.api'; sed -n '/^-- Gordon handoff files/,$p' "$REPO_ROOT/.config/nvim/lua/autocommands.lua"; } \
    > "$BATS_TEST_TMPDIR/block.lua"
}

save_in_nvim() { # save_in_nvim <file>
  printf 'x\n' > "$1"
  timeout 30 nvim --headless -u NONE "$1" \
    -c "luafile $BATS_TEST_TMPDIR/block.lua" \
    -c 'normal! Ay' -c 'write' \
    -c 'lua vim.wait(3000, function() return vim.fn.filereadable(vim.env.BATS_TEST_TMPDIR .. "/save.calls") == 1 end, 50)' \
    -c 'qa!'
}

@test "saving a handoff file runs save with its path" {
  mkdir -p "$HOME/.local/state/gordon/handoffs"
  save_in_nvim "$HOME/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md"
  [ "$(cat "$BATS_TEST_TMPDIR/save.calls")" = "save $HOME/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md" ]
}

@test "saving an archived handoff runs save with its path" {
  mkdir -p "$HOME/.local/state/gordon/handoffs/archive"
  save_in_nvim "$HOME/.local/state/gordon/handoffs/archive/11111111-1111-4111-8111-111111111111.md"
  [ "$(cat "$BATS_TEST_TMPDIR/save.calls")" = "save $HOME/.local/state/gordon/handoffs/archive/11111111-1111-4111-8111-111111111111.md" ]
}

@test "saving any other file does not" {
  save_in_nvim "$BATS_TEST_TMPDIR/other.md"
  [ ! -e "$BATS_TEST_TMPDIR/save.calls" ]
}

@test "saving the legacy combined file still ingests replies during transition" {
  save_in_nvim "$HOME/.local/state/gordon/handoffs.md"
  [ "$(cat "$BATS_TEST_TMPDIR/save.calls")" = "save" ]
}
