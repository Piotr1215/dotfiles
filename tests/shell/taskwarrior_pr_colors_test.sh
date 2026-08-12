#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_data="$(mktemp -d /tmp/taskwarrior-pr-colors-test.XXXXXX)"
trap 'rm -rf "$test_data"' EXIT
export TASKRC="$repo_root/.taskrc"

task_cmd=(task rc.data.location="$test_data" rc.hooks=off rc.confirmation=off)

"${task_cmd[@]}" add project:issues +kill "closable issue proof" >/dev/null 2>&1
"${task_cmd[@]}" add project:pr-reviews +kill +pr "disposable PR proof" >/dev/null 2>&1
"${task_cmd[@]}" add project:pr-reviews +kill +pr +pr_approved "approved PR proof" >/dev/null 2>&1

report=$("${task_cmd[@]}" rc.color=on rc._forcecolor=on rc.verbose=nothing rc.defaultwidth=200 list 2>/dev/null)
issue_row=$(grep -F "closable issue proof" <<<"$report")
pr_row=$(grep -F "disposable PR proof" <<<"$report")
approved_row=$(grep -F "approved PR proof" <<<"$report")

[[ "$issue_row" == *$'\033[1;38;5;7;48;5;52m'* ]]
[[ "$pr_row" == *$'\033[1;38;5;4;48;5;0m'* ]]
[[ "$approved_row" == *$'\033[1;38;5;2;48;5;0m'* ]]

grep -Fqx "color.tag.pr          = bold blue on black" "$repo_root/.taskrc"
grep -Fqx "color.tag.pr_approved = bold green on black" "$repo_root/.taskrc"
grep -Fqx "rule.precedence.color=tag.pr_approved,tag.pr,tag.kill,tag.review,deleted,completed,active,keyword.,tag.,project.,overdue,scheduled,due.today,due,blocked,blocking,recurring,tagged,uda." "$repo_root/.taskrc"

printf '%s\n' "taskwarrior PR color precedence tests passed"
