#!/usr/bin/env bash
set -eo pipefail

# Exercise build and install behavior without network access or a real installation.
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/stubs"

cat > "$test_root/stubs/git" <<'STUB'
#!/usr/bin/env bash
set -eo pipefail
printf 'git %s\n' "$*" >> "$TEST_LOG"
if [[ "$1" == clone || "$1" == init ]]; then
  mkdir -p -- "${@: -1}"
elif [[ "$1" == -C && "$3" == rev-parse ]]; then
  printf '%s\n' "${TEST_SHA:-aeb778fae3c7b1a5c29d0f9b4cc2febfe09797d6}"
elif [[ "$1" != -C || ( "$3" != apply && "$3" != fetch && "$3" != checkout ) ]]; then
  exit 1
fi
STUB
cat > "$test_root/stubs/cargo" <<'STUB'
#!/usr/bin/env bash
set -eo pipefail
printf 'cargo %s\n' "$*" >> "$TEST_LOG"
fixture_dir="$PWD/tests/data"
[[ "$fixture_dir" == "$XDG_CACHE_HOME/taskwarrior-tui-build/source."*/tests/data ]]
[[ "$TASKDATA" == "$fixture_dir/.task" ]]
[[ "$TASKRC" == "$fixture_dir/.taskrc" ]]
[[ "$TASKWARRIOR_TUI_CONFIG" == "$fixture_dir/.config" ]]
[[ "$TASKWARRIOR_TUI_DATA" == "$fixture_dir/.data" ]]
[[ "$XDG_RUNTIME_DIR" == "$fixture_dir/runtime" && -d "$XDG_RUNTIME_DIR" ]]
[[ "$RUST_TEST_THREADS" == 1 ]]
if [[ "$1" == test && "${FAIL_TEST:-0}" == 1 ]]; then
  exit 1
fi
if [[ "$1" == build ]]; then
  target="${@: -1}"
  mkdir -p -- "$target/release"
  printf 'new binary\n' > "$target/release/taskwarrior-tui"
fi
STUB
chmod +x "$test_root/stubs/git" "$test_root/stubs/cargo"

# Give each case a separate home, binary, target, and call log.
setup_case() {
  local name="$1"
  test_home="$test_root/$name/home with spaces"
  export XDG_CACHE_HOME="$test_home/cache with spaces"
  export XDG_STATE_HOME="$test_home/state with spaces"
  export CARGO_TARGET_DIR="$test_home/target with spaces"
  export TEST_LOG="$test_root/$name/calls"
  export PATH="$test_root/stubs:$test_home/bin:$base_path"
  mkdir -p -- "$test_home/bin"
  printf 'original binary\n' > "$test_home/bin/taskwarrior-tui"
  chmod +x "$test_home/bin/taskwarrior-tui"
  : > "$TEST_LOG"
  unset FAIL_TEST TEST_SHA
}

assert_original() {
  [[ "$(cat "$test_home/bin/taskwarrior-tui")" == 'original binary' ]]
  [[ ! -d "$XDG_STATE_HOME/taskwarrior-tui/backups" ]]
}

base_path="$PATH"
setup_case build_only
env HOME="$test_home" bash "$repo_dir/scripts/__build_taskwarrior_tui.sh" > /dev/null
assert_original
[[ "$(cat "$CARGO_TARGET_DIR/release/taskwarrior-tui")" == 'new binary' ]]
[[ "$(grep -c '^git .* apply ' "$TEST_LOG")" == 2 ]]
grep -q '^cargo test ' "$TEST_LOG"
grep -q '^cargo build ' "$TEST_LOG"

setup_case install
env HOME="$test_home" bash "$repo_dir/scripts/__build_taskwarrior_tui.sh" --install > /dev/null
[[ "$(cat "$test_home/bin/taskwarrior-tui")" == 'new binary' ]]
shopt -s nullglob
backups=("$XDG_STATE_HOME/taskwarrior-tui/backups/"*)
[[ ${#backups[@]} == 1 ]]
[[ "$(cat "${backups[0]}")" == 'original binary' ]]

setup_case test_failure
export FAIL_TEST=1
if env HOME="$test_home" bash "$repo_dir/scripts/__build_taskwarrior_tui.sh" --install > /dev/null 2>&1; then
  printf 'cargo test failure unexpectedly succeeded\n' >&2
  exit 1
fi
assert_original
if grep -q '^cargo build ' "$TEST_LOG"; then exit 1; fi

setup_case wrong_sha
export TEST_SHA=incorrect
if env HOME="$test_home" bash "$repo_dir/scripts/__build_taskwarrior_tui.sh" --install > /dev/null 2>&1; then
  printf 'wrong upstream SHA unexpectedly succeeded\n' >&2
  exit 1
fi
assert_original
if grep -q '^cargo ' "$TEST_LOG"; then exit 1; fi
if grep -q '^git .* apply ' "$TEST_LOG"; then exit 1; fi
printf '4 build and install cases passed\n'
