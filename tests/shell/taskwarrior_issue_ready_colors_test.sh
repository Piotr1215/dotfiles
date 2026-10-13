#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_data="$(mktemp -d /tmp/taskwarrior-issue-ready-colors-test.XXXXXX)"
trap 'rm -rf "$test_data"' EXIT
export TASKRC="$repo_root/.taskrc"

task_cmd=(task rc.data.location="$test_data" rc.hooks=off rc.confirmation=off)

"${task_cmd[@]}" add project:issues +issue_ready "closable issue proof" >/dev/null 2>&1
"${task_cmd[@]}" add project:issues +fresh "fresh issue proof" >/dev/null 2>&1

# The close candidate keeps its dark ground under the real theme.
themed=$("${task_cmd[@]}" rc.color=on rc._forcecolor=on rc.verbose=nothing rc.defaultwidth=200 list 2>/dev/null)
grep -F "closable issue proof" <<<"$themed" | grep -q "48;5;52"
if grep -F "fresh issue proof" <<<"$themed" | grep -q "48;5;52"; then
  echo "FAIL: a non-candidate row carries the close-candidate ground" >&2
  exit 1
fi

grep -Fqx "color.tag.issue_ready = bold white on color52" "$repo_root/.taskrc"
grep -Fq "rule.precedence.color=tag.issue_ready,tag.review," "$repo_root/.taskrc"
! grep -Fq "color.tag.kill " "$repo_root/.taskrc"

# The syncer must stamp the marker the colour rule keys off.
grep -Fq 'modify "$task_uuid" +issue_ready' "$repo_root/scripts/__github_issue_sync.sh"
grep -Fq 'index("issue_ready")' "$repo_root/scripts/__github_issue_sync.sh"

printf '%s\n' "taskwarrior issue_ready color tests passed"
