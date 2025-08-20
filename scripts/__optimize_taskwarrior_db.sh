#!/usr/bin/env bash
set -eo pipefail

DB_PATH="${HOME}/.task/taskchampion.sqlite3"
LOCK_FILE="/tmp/taskwarrior_db_optimize.lock"
LOG_FILE="${HOME}/.task/optimize.log"

cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

if [[ -f "$LOCK_FILE" ]]; then
    echo "$(date): Optimization already running" >> "$LOG_FILE"
    exit 0
fi

touch "$LOCK_FILE"

if [[ ! -f "$DB_PATH" ]]; then
    echo "$(date): Error: Database not found at $DB_PATH" >> "$LOG_FILE"
    exit 1
fi

if pgrep -x "task" > /dev/null || pgrep -x "taskwarrior-tui" > /dev/null; then
    echo "$(date): Taskwarrior or TUI is running, skipping optimization" >> "$LOG_FILE"
    exit 0
fi

echo "$(date): Starting optimization" >> "$LOG_FILE"

sqlite3 "$DB_PATH" <<EOF 2>> "$LOG_FILE"
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;
PRAGMA mmap_size = 30000000000;
PRAGMA optimize;
VACUUM;
ANALYZE;
EOF

if [[ $? -eq 0 ]]; then
    echo "$(date): Optimization complete" >> "$LOG_FILE"
else
    echo "$(date): Optimization failed" >> "$LOG_FILE"
fi