#!/usr/bin/env bats

setup() {
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/tests/bats" "$WORK/tests/shell"
  cp "${BATS_TEST_DIRNAME}/../run_ci.sh" "$WORK/tests/run_ci.sh"
  RUN_CI="$WORK/tests/run_ci.sh"

  printf '@test "passes" { true; }\n' >"$WORK/tests/bats/pass_test.bats"
  printf '@test "fails" { false; }\n' >"$WORK/tests/bats/fail_test.bats"
}

teardown() {
  rm -rf "$WORK"
}

@test "a failing file fails the suite and is named" {
  run "$RUN_CI" bats
  [ "$status" -eq 1 ]
  [[ "$output" == *"bats: ran 2, skipped 0, failed 1"* ]]
  [[ "$output" == *"FAILED tests/bats/fail_test.bats"* ]]
}

@test "a file in the skip list never runs" {
  printf '# reason header\ntests/bats/fail_test.bats  # broken on purpose\n' >"$WORK/tests/ci_skip.txt"
  run "$RUN_CI" bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip tests/bats/fail_test.bats"* ]]
  [[ "$output" == *"bats: ran 1, skipped 1, failed 0"* ]]
}

@test "a shell test with a zsh shebang runs under zsh" {
  command -v zsh >/dev/null || skip "zsh not installed"
  printf '#!/usr/bin/env zsh\nprint -r -- ok\n' >"$WORK/tests/shell/zsh_only_test.sh"
  run "$RUN_CI" shell
  [ "$status" -eq 0 ]
  [[ "$output" == *"shell: ran 1, skipped 0, failed 0"* ]]
}

@test "an unknown suite is an error" {
  run "$RUN_CI" nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown suite: nope"* ]]
}
