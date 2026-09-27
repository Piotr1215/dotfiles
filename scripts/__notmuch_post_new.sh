#!/usr/bin/env bash
# notmuch post-new hook: tag recent inbox mail with semif verdicts (plan #183).
# semif/bulk answers "Is this email a newsletter?", semif/action "Does this
# email need a reply or action from me?", and semif/scored marks mail both
# answered. Shadow: nothing acts on these tags yet. notmuch new must never
# fail here, so every path exits 0.
set -eo pipefail

# cron runs mailsync with a bare PATH, and semif lives in ~/.local/bin.
PATH="${HOME}/.local/bin:${PATH}"
command -v semif >/dev/null 2>&1 || exit 0

err_log="${XDG_STATE_HOME:-${HOME}/.local/state}/semif/notmuch.err"
mkdir -p "${err_log%/*}" 2>/dev/null || exit 0
# A host that stays down writes one line a run; keep the file small.
if [[ "$(stat -c %s "$err_log" 2>/dev/null || echo 0)" -gt 1048576 ]]; then
  : > "$err_log" || true
fi

timeout 180 semif notmuch email-bulk=bulk email-action=action >/dev/null 2>>"$err_log" || true
exit 0
