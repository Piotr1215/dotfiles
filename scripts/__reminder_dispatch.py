#!/usr/bin/env python3
"""Spread frequent reminder checks over one serialized five-minute window."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

INTERVAL = 300
SPACING = 10
ID = re.compile(r"^[0-9a-f]{8}$")


def eligible(record):
    repeat = record.get("repeat", "")
    interval = re.fullmatch(r"every ([0-9]+)m", repeat) if isinstance(repeat, str) else None
    return (record.get("status") == "active" and record.get("action") == "exec"
            and isinstance(repeat, str)
            and (repeat == "* * * * *" or (interval is not None and int(interval[1]) < 5)))


def load_ids(store):
    records = {}
    with open(store, encoding="utf-8") as source:
        for line in source:
            if line.strip():
                record = json.loads(line)
                records[record["id"]] = record
    return [key for key, record in records.items() if ID.fullmatch(key) and eligible(record)]


def slots(ids):
    # Hash order is stable for a given roster; evenly spaced positions avoid
    # collisions. More than 30 checks extend into the following window.
    order = sorted(ids, key=lambda key: hashlib.sha256(key.encode()).digest())
    step = max(SPACING, INTERVAL // max(len(order), 1))
    return [(key, index * step) for index, key in enumerate(order)]


def dispatch(store, state_dir, runner, reminder, clock=time.time, sleep=time.sleep,
             run=subprocess.run):
    state_dir = Path(state_dir)
    state_dir.mkdir(parents=True, exist_ok=True)
    with (state_dir / "dispatch.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        scheduled = slots(load_ids(store))
        window = int(clock() // INTERVAL) * INTERVAL
        stamps = state_dir / "dispatch-attempts"
        stamps.mkdir(exist_ok=True)
        previous_start = None
        for key, offset in scheduled:
            stamp = stamps / key
            try:
                last = float(stamp.read_text(encoding="ascii"))
            except FileNotFoundError:
                last = float("-inf")
            target = max(window + offset, last + INTERVAL)
            if previous_start is not None:
                target = max(target, previous_start + SPACING)
            # A not-yet-due check waits for the next dispatcher, not an extra
            # full interval in this window. The stamp remains authoritative.
            if target >= window + INTERVAL and len(scheduled) <= INTERVAL // SPACING:
                continue
            delay = target - clock()
            if delay > 0:
                sleep(delay)
            started = clock()
            temporary = stamp.with_suffix(".tmp")
            with temporary.open("w", encoding="ascii") as output:
                output.write(str(started))
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, stamp)
            previous_start = started
            env = os.environ.copy()
            env.update(REMINDER_STORE=str(store), REMINDER_STATE_DIR=str(state_dir))
            run([runner, "remind-" + key, "--", reminder, "fire", key], check=False, env=env)


def main():
    parser = argparse.ArgumentParser()
    for flag in ("store", "state-dir", "runner", "reminder"):
        parser.add_argument("--" + flag, required=True)
    args = parser.parse_args()
    dispatch(args.store, args.state_dir, args.runner, args.reminder)


if __name__ == "__main__":
    main()
