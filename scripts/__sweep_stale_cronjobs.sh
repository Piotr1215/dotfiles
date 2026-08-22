#!/usr/bin/env bash
# PROJECT: cron-manager
#
# Boot-time entry point: heal every stale `running` marker under
# ~/.local/state/cron-jobs/.
#
# __cron_run.sh publishes a `running` marker (job, ts, pid) before a wrapped
# command starts, and only overwrites it with a final state (no-hit/hit/
# error/interrupted) once that command exits. A job killed outright, most
# often by the nightly poweroff's SIGKILL, never reaches that final write: its
# marker is left saying "running" against a pid that no longer exists. Nothing
# else clears it. The job's own next scheduled run heals its own marker on
# start, but for a weekly job that is up to a week away, and the dashboard
# would show it in-flight the whole time.
#
# This is that missing beat. It runs once at boot, after the crash that would
# have caused the staleness, and sweeps every marker: each one whose pid is no
# longer that job's wrapper gets rewritten as `interrupted` (see
# __cron_run.sh's cron_run_heal_stale_marker for the healing logic itself;
# --sweep-stale is its batch entry point, kept in the wrapper because that is
# where the per-marker logic already lives).
#
# Usage (crontab):
#   @reboot /path/__sweep_stale_cronjobs.sh
set -eo pipefail

exec "$(dirname "${BASH_SOURCE[0]}")/__cron_run.sh" --sweep-stale
