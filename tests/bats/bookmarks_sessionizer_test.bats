#!/usr/bin/env bats

# The sessionizer decides file-vs-directory and hands tmux a working directory.
# `fzf` and `tmux` are stubbed so the decision is observable without a terminal.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SESSIONIZER="$REPO_ROOT/scripts/__bookmarks_sessionizer.sh"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  TMUX_LOG="$BATS_TEST_TMPDIR/tmux.log"
  export BOOKMARKS_FILE="$BATS_TEST_TMPDIR/bookmarks.conf"
  mkdir -p "$STUB_BIN"

  # tmux: record the call, and report no existing sessions.
  cat > "$STUB_BIN/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMUX_LOG"
[ "\$1" = list-sessions ] && exit 1
exit 0
EOF
  chmod +x "$STUB_BIN/tmux"
}

# fzf returns the bookmark line the test wants selected.
stub_fzf() {
  cat > "$STUB_BIN/fzf" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$1"
EOF
  chmod +x "$STUB_BIN/fzf"
}

run_sessionizer() {
  run env PATH="$STUB_BIN:$PATH" TMUX= BOOKMARKS_FILE="$BOOKMARKS_FILE" \
    bash "$SESSIONIZER"
}

@test "a directory bookmark opens a session in that directory" {
  mkdir -p "$BATS_TEST_TMPDIR/custom_patterns"
  printf 'fabric custom patterns;%s\n' "$BATS_TEST_TMPDIR/custom_patterns" > "$BOOKMARKS_FILE"
  stub_fzf "fabric custom patterns;$BATS_TEST_TMPDIR/custom_patterns"

  run_sessionizer

  [ "$status" -eq 0 ]
  grep -F "new-session -s custom_patterns -c $BATS_TEST_TMPDIR/custom_patterns" "$TMUX_LOG"
  ! grep -q nvim "$TMUX_LOG"
}

@test "a file bookmark opens nvim on it from the containing directory" {
  mkdir -p "$BATS_TEST_TMPDIR/dir"
  touch "$BATS_TEST_TMPDIR/dir/notes.md"
  printf 'notes;%s\n' "$BATS_TEST_TMPDIR/dir/notes.md" > "$BOOKMARKS_FILE"
  stub_fzf "notes;$BATS_TEST_TMPDIR/dir/notes.md"

  run_sessionizer

  [ "$status" -eq 0 ]
  grep -F -- "new-session -s notes_md -c $BATS_TEST_TMPDIR/dir nvim '$BATS_TEST_TMPDIR/dir/notes.md'" "$TMUX_LOG"
}

# `file -b` on a missing path says "No such file or directory", and the old
# substring check saw "directory" in that and opened a session in a path that is
# not there.
@test "a bookmark that does not resolve fails loudly instead of posing as a directory" {
  printf 'stale;%s\n' "$BATS_TEST_TMPDIR/gone.html" > "$BOOKMARKS_FILE"
  stub_fzf "stale;$BATS_TEST_TMPDIR/gone.html"

  run_sessionizer

  [ "$status" -eq 1 ]
  [[ "$output" == *"does not resolve"* ]]
  [ ! -s "$TMUX_LOG" ]
}

@test "cancelling the picker exits quietly without touching tmux" {
  : > "$BOOKMARKS_FILE"
  stub_fzf ""

  run_sessionizer

  [ "$status" -eq 0 ]
  [ ! -s "$TMUX_LOG" ]
}
