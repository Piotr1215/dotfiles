#!/usr/bin/env bats

# The models.env completion source parses the role from the line and asks
# ~/.claude/scripts/__models.sh for ids. Headless, no plugins, so it needs
# neither cmp nor a terminal.

@test "models.env completion resolves roles and candidates" {
  run nvim --headless -u NONE -l "${BATS_TEST_DIRNAME}/../nvim/models_completion_test.lua"
  [ "$status" -eq 0 ]
  [[ "$output" != *FAIL* ]]
}
