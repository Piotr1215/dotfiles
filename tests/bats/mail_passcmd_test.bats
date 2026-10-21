#!/usr/bin/env bats

# __mail_passcmd.sh against a throwaway mbsync config whose PassCmds print
# fixed strings, never the live ~/.mbsyncrc.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__mail_passcmd.sh"
  WORK="$(mktemp -d)"
  export MAIL_PASSCMD_MBSYNCRC="${WORK}/mbsyncrc"
  cat >"$MAIL_PASSCMD_MBSYNCRC" <<'EOF'
IMAPStore a@example.com-remote
Host imap.example.com
User a@example.com
PassCmd "printf 'pw-a'"

MaildirStore a@example.com-local
Path /tmp/a/

IMAPStore b@example.com-remote
Host imap.example.com
User b@example.com
PassCmd "+echo \"pw b\""

Channel b@example.com
Far :b@example.com-remote:
EOF
}

teardown() {
  rm -rf "$WORK"
}

@test "runs the PassCmd of the matching store" {
  run "$SCRIPT" a@example.com
  [ "$status" -eq 0 ]
  [ "$output" = "pw-a" ]
}

@test "handles mbsync's escaped quotes and interactive prefix" {
  run "$SCRIPT" b@example.com
  [ "$status" -eq 0 ]
  [ "$output" = "pw b" ]
}

@test "an unknown account fails without running anything" {
  run "$SCRIPT" c@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"no IMAPStore with User c@example.com"* ]]
}

@test "the error never prints a PassCmd" {
  run "$SCRIPT" c@example.com
  [[ "$output" != *printf* ]]
  [[ "$output" != *echo* ]]
}

@test "missing argument prints usage" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *usage* ]]
}
