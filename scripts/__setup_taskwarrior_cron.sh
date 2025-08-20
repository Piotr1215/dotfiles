#!/usr/bin/env bash
set -eo pipefail

SCRIPT_PATH="${HOME}/dev/dotfiles/scripts/__optimize_taskwarrior_db.sh"
CRON_ENTRY="0 15 * * 0 ${SCRIPT_PATH} # Weekly Taskwarrior DB optimization (Sundays 3 PM)"

if ! crontab -l 2>/dev/null | grep -q "__optimize_taskwarrior_db.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
    echo "Added weekly optimization cron job (Sundays at 3 PM)"
else
    echo "Cron job already exists"
fi

echo "Current cron jobs:"
crontab -l | grep -E "(task|optimize)" || echo "No taskwarrior-related cron jobs found"