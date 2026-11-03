#!/usr/bin/env python3
"""Spread opted-in cron launches and serialize claims across all jobs."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def plain_reminder(job):
    if not job.startswith('remind-'):
        return False
    store = Path(os.environ.get('REMINDER_STORE', '~/.local/state/reminders/reminders.jsonl')).expanduser()
    record = None
    try:
        with store.open() as source:
            for line in source:
                try:
                    value = json.loads(line)
                except ValueError:
                    continue
                if isinstance(value, dict) and value.get('id') == job[7:]:
                    record = value
    except OSError:
        return False
    return record is not None and record.get('action', 'show') in ('show', 'open')


def pace(argv, state_dir, *, now=time.time, sleep=time.sleep, launch=subprocess.run):
    wrapper, job = argv[:2]
    state_dir = Path(state_dir)
    state_dir.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256(job.encode()).hexdigest()
    with (state_dir / (key + '.lock')).open('a') as job_lock:
        try:
            fcntl.flock(job_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        env = os.environ.copy()
        env['CRON_PACED_ACTIVE'] = '1'
        if plain_reminder(job):
            result = launch([wrapper, *argv[1:]], env=env)
            return result.returncode if result.returncode >= 0 else 128 - result.returncode
        # The dispatcher spreads its own children across the five-minute window.
        # It still needs this scope and duplicate guard, but no extra jitter.
        sleep(0 if job == 'reminder-dispatch' else int(key[:8], 16) % 241)
        with (state_dir / 'claims.lock').open('a+') as claims:
            fcntl.flock(claims, fcntl.LOCK_EX)
            claims.seek(0)
            try:
                previous = float(claims.read().strip())
            except ValueError:
                previous = 0
            delay = max(0, previous + 5 - now())
            if delay:
                sleep(delay)
            claims.seek(0)
            claims.truncate()
            claims.write(str(now()))
            claims.flush()
        result = launch(['systemd-run', '--user', '--scope', '--quiet',
                         '--slice=background-automation.slice', '-p', 'CPUQuota=30%',
                         '/usr/bin/nice', '-n', '10', wrapper, *argv[1:]], env=env)
        return result.returncode if result.returncode >= 0 else 128 - result.returncode


def main():
    if len(sys.argv) < 4:
        print('usage: __cron_pace.py wrapper job -- command...', file=sys.stderr)
        return 64
    state = os.environ.get('CRON_STATE_DIR', os.path.expanduser('~/.local/state/cron-jobs'))
    return pace(sys.argv[1:], Path(state) / '.pacing')


if __name__ == '__main__':
    sys.exit(main())
