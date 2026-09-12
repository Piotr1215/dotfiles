#!/usr/bin/env bash
# PROJECT: cron-manager
#
# Open the crontab in nvim with the cursor on one job's line, and install the
# result when the buffer changed. The click action behind the description
# line of every row in the cron-status widget: "what is this" is answered by
# the comment above the job, so the comment is where a person goes to change
# it, add a job next to it, or move its time.
#
# Not `crontab -e`. Its temp file has no stable name to pass a `+line` to, and
# it hung under a non-interactive EDITOR on this box while being tested. This
# does the same three steps in the open: dump, edit, `crontab <file>`, which
# validates the syntax and refuses a broken file the same way -e does. An
# unchanged buffer installs nothing.
#
# Usage: __cron_edit.sh [<job-name>]
#   With no job the cursor lands on the first line.
set -eo pipefail

job="${1:-}"
tmp=$(mktemp --suffix=.crontab)
trap 'rm -f "$tmp"' EXIT

crontab -l >"$tmp" 2>/dev/null || : >"$tmp"

line=1
if [ -n "$job" ]; then
    # The wrapped line naming exactly this job (trailing space guards `foo`
    # against `foo-full`). Fall back to the first mention for legacy lines.
    line=$(grep -nF "__cron_run.sh ${job} " "$tmp" | grep -v '^[0-9]*:[[:space:]]*#' | head -1 | cut -d: -f1 || true)
    [ -n "$line" ] || line=$(grep -nF "$job" "$tmp" | head -1 | cut -d: -f1 || true)
    [ -n "$line" ] || line=1
fi

before=$(sha256sum "$tmp" | cut -d' ' -f1)
nvim "+${line}" "$tmp"
after=$(sha256sum "$tmp" | cut -d' ' -f1)

if [ "$before" = "$after" ]; then
    echo "crontab unchanged."
    exit 0
fi

# `crontab <file>` validates and installs, or refuses with the parse error
# and leaves the current crontab as it was. Keep the edit for a retry.
if crontab "$tmp"; then
    echo "crontab installed."
else
    keep="${HOME}/.local/state/cron-jobs/crontab.rejected"
    cp "$tmp" "$keep"
    echo "crontab NOT installed; your edit is at ${keep}" >&2
    read -r -p "press enter to close"
    exit 1
fi
