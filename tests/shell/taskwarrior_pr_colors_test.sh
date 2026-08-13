#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_data="$(mktemp -d /tmp/taskwarrior-pr-colors-test.XXXXXX)"
trap 'rm -rf "$test_data"' EXIT
export TASKRC="$repo_root/.taskrc"

task_cmd=(task rc.data.location="$test_data" rc.hooks=off rc.confirmation=off)

"${task_cmd[@]}" add project:issues +issue_ready "closable issue proof" >/dev/null 2>&1
"${task_cmd[@]}" add project:pr-reviews +kill +pr "disposable PR proof" >/dev/null 2>&1
"${task_cmd[@]}" add project:pr-reviews +pr "plain PR proof" >/dev/null 2>&1
"${task_cmd[@]}" add project:pr-reviews +kill +pr +fresh "fresh PR proof" >/dev/null 2>&1
"${task_cmd[@]}" add project:pr-reviews +kill +pr +pr_approved "approved PR proof" >/dev/null 2>&1

# color.alternate is cleared here only so the escapes do not depend on row
# parity: the theme grounds every second row, which switches taskwarrior from
# the "1;33m" form to "1;38;5;3;48;5;234m". The close-candidate ground is
# checked separately below, under the real theme.
report=$("${task_cmd[@]}" rc.color=on rc._forcecolor=on rc.color.alternate= rc.verbose=nothing rc.defaultwidth=200 list 2>/dev/null)
issue_row=$(grep -F "closable issue proof" <<<"$report")
pr_row=$(grep -F "disposable PR proof" <<<"$report")
plain_row=$(grep -F "plain PR proof" <<<"$report")
fresh_row=$(grep -F "fresh PR proof" <<<"$report")
approved_row=$(grep -F "approved PR proof" <<<"$report")

# +kill means "disposable PR mirror" and carries no colour, so a PR row that has
# it is indistinguishable from one that does not. This is the whole point of
# splitting it from the close-candidate marker: colour rules merge field by
# field, so while one tag carried both meanings its ground could not be lifted
# off the PR rows without painting over them and flattening the report.
for row in "$pr_row" "$plain_row"; do
  if grep -qE $'\033\[' <<<"$row"; then
    echo "FAIL: a PR row is coloured by +kill" >&2
    exit 1
  fi
done

# +fresh still reaches a PR row that carries +kill.
[[ "$fresh_row" == *$'\033[1;33m'* ]]
[[ "$approved_row" == *$'\033[1;32m'* ]]

# The close candidate keeps its ground, and no PR row may borrow it.
themed=$("${task_cmd[@]}" rc.color=on rc._forcecolor=on rc.verbose=nothing rc.defaultwidth=200 list 2>/dev/null)
grep -F "closable issue proof" <<<"$themed" | grep -q "48;5;52"
if grep -F "48;5;52" <<<"$themed" | grep -qF "PR proof"; then
  echo "FAIL: a PR row carries the close-candidate ground" >&2
  exit 1
fi

grep -Fqx "color.tag.issue_ready = bold white on color52" "$repo_root/.taskrc"
grep -Fq "rule.precedence.color=tag.issue_ready,tag.review," "$repo_root/.taskrc"
! grep -Fq "color.tag.kill " "$repo_root/.taskrc"

# The syncer must stamp the marker the colour rule keys off.
grep -Fq 'modify "$task_uuid" +issue_ready' "$repo_root/scripts/__github_issue_sync.sh"
grep -Fq 'index("issue_ready")' "$repo_root/scripts/__github_issue_sync.sh"

printf '%s\n' "taskwarrior PR color tests passed"
