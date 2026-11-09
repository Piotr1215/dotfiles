#!/usr/bin/env bash
set -eo pipefail

# Rebuild the pinned Twoy source and run its tests before optional installation.
main() {
  local install_binary=false
  case "${1:-}" in
    '') ;;
    --install) install_binary=true ;;
    *) printf 'Usage: %s [--install]\n' "$0" >&2; return 2 ;;
  esac
  [[ $# -le 1 ]] || return 2

  local script_dir patch_dir build_root source_dir target_dir fixture_dir install_path backup_dir backup_path staged
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  patch_dir="$script_dir/../patches/taskwarrior-tui"
  build_root="${XDG_CACHE_HOME:-$HOME/.cache}/taskwarrior-tui-build"
  mkdir -p -- "$build_root"
  source_dir="$(mktemp -d "$build_root/source.XXXXXX")"
  target_dir="${CARGO_TARGET_DIR:-$build_root/target}"
  [[ "$target_dir" = /* ]] || { printf 'CARGO_TARGET_DIR must be absolute\n' >&2; return 2; }

  git clone --quiet --depth 1 --branch v0.27.0 https://github.com/kdheepak/taskwarrior-tui.git "$source_dir"
  [[ "$(git -C "$source_dir" rev-parse HEAD)" = aeb778fae3c7b1a5c29d0f9b4cc2febfe09797d6 ]] || {
    printf 'Upstream v0.27.0 changed; refusing to build\n' >&2
    return 1
  }
  git -C "$source_dir" apply "$patch_dir/0001-installed-customizations.patch"
  git -C "$source_dir" apply "$patch_dir/0002-handoff-selection.patch"
  fixture_dir="$source_dir/tests/data"
  git init --quiet "$fixture_dir"
  git -C "$fixture_dir" fetch --quiet --depth 1 https://github.com/kdheepak/taskwarrior-testdata cdcdb20de1e9aefb2e2b50de7bbd27388b41f80e
  git -C "$fixture_dir" checkout --quiet --detach FETCH_HEAD
  mkdir -m 0700 -- "$fixture_dir/runtime"
  (
    cd -- "$source_dir"
    # Upstream tests delete TASKDATA. Keep every test path inside fresh fixtures.
    export TASKRC="$fixture_dir/.taskrc" TASKDATA="$fixture_dir/.task"
    export TASKWARRIOR_TUI_CONFIG="$fixture_dir/.config" TASKWARRIOR_TUI_DATA="$fixture_dir/.data"
    export XDG_RUNTIME_DIR="$fixture_dir/runtime" TMUX_PANE='%99999' RUST_TEST_THREADS=1
    cargo test --locked --target-dir "$target_dir"
    cargo build --locked --release --target-dir "$target_dir"
  )
  printf 'Built and tested: %s\nSource: %s\n' "$target_dir/release/taskwarrior-tui" "$source_dir"
  "$install_binary" || return 0

  install_path="$(command -v taskwarrior-tui)"
  [[ "$install_path" = "$HOME/"* && -f "$install_path" && ! -L "$install_path" ]] || {
    printf 'Refusing to replace a binary outside HOME, a symlink, or a missing file: %s\n' "$install_path" >&2
    return 1
  }
  backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tui/backups"
  mkdir -p -- "$backup_dir"
  backup_path="$backup_dir/taskwarrior-tui.$(date +%Y%m%dT%H%M%S).$$"
  cp -p -- "$install_path" "$backup_path"
  cmp -s -- "$install_path" "$backup_path"
  staged="$(mktemp "${install_path}.new.XXXXXX")"
  install -m 0755 -- "$target_dir/release/taskwarrior-tui" "$staged"
  mv -f -- "$staged" "$install_path"
  printf 'Installed: %s\nBackup: %s\n' "$install_path" "$backup_path"
}

main "$@"
