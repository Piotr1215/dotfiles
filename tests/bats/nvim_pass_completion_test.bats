#!/usr/bin/env bats

# The .envrc pass completion source lists password-store entry names and
# expands `pass<filter>` into a `_pass_export NAME entry` line. Headless, no
# plugins, against a fixture store.

@test ".envrc pass completion lists entries and builds export lines" {
  run nvim --headless -u NONE -l "${BATS_TEST_DIRNAME}/../nvim/pass_completion_test.lua"
  [ "$status" -eq 0 ]
  [[ "$output" != *FAIL* ]]
}
