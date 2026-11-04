#!/usr/bin/env bats
@test "legacy editor integration and bookmark are retired" {
  root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ! grep -q 'GordonHandoffs\|__handoffs_file.py' "$root/.config/nvim/lua/autocommands.lua"
  ! grep -q '^gordon handoffs;' "$root/scripts/__bookmarks.conf"
  ! grep -q -- '--actions' "$root/.config/alacritty/alacritty.toml"
}
