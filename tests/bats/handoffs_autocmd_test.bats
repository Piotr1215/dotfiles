#!/usr/bin/env bats
# The nvim BufWritePost autocmd for the Gordon handoffs file runs
# `__handoffs_file.py save` for that exact path and for no other file.

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
  { echo 'local api = vim.api'; sed -n '/^-- Gordon handoffs file/,$p' "$REPO_ROOT/.config/nvim/lua/autocommands.lua"; } \
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

@test "saving the handoffs file runs save once" {
  save_in_nvim "$HOME/.local/state/gordon/handoffs.md"
  [ "$(cat "$BATS_TEST_TMPDIR/save.calls")" = "save" ]
}

@test "saving any other file does not" {
  save_in_nvim "$BATS_TEST_TMPDIR/other.md"
  [ ! -e "$BATS_TEST_TMPDIR/save.calls" ]
}
