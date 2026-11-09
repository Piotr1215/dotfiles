#!/usr/bin/env python3
"""Exercise the installed selection signal with isolated tasks in detached tmux."""

import argparse
import json
import re
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import time
import uuid


def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", nargs="?", default=shutil.which("taskwarrior-tui"))
    parser.add_argument("--start-hook", type=Path, help="Copy this hook into the isolated task database")
    args = parser.parse_args()
    binary = args.binary
    root = Path(tempfile.mkdtemp(prefix="twoy-selection-smoke-"))
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    test_home = root / "home"
    helper = test_home / "dev/dotfiles/scripts/__handoff_navigate.sh"
    helper.parent.mkdir(parents=True)
    helper.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$HANDOFF_NAV_LOG"\n')
    helper.chmod(0o755)
    nav_log = root / "navigation.log"
    rc = root / "taskrc"
    rc.write_text(
        f"data.location={root / 'tasks'}\nconfirmation=no\nhooks={'on' if args.start_hook else 'off'}\n"
        "report.signal.columns=id,description\nreport.signal.labels=ID,Description\n"
        "report.signal.sort=id+\nreport.signal.filter=status:pending\n"
        "uda.taskwarrior-tui.task-report.show-info=false\n"
        "uda.taskwarrior-tui.tick-rate=100\n"
    )
    env = dict(os.environ, TASKRC=str(rc), TASKDATA=str(root / "tasks"))
    if args.start_hook:
        hooks = root / "tasks/hooks"
        hooks.mkdir(parents=True)
        shutil.copy2(args.start_hook, hooks / "on-modify-handoff.py")
    tasks = [
        {"uuid": str(uuid.uuid4()), "description": f"signal-task-{n:02d}",
         "status": "pending", "entry": "20260101T000000Z"}
        for n in range(45)
    ]
    tasks[0]["tags"] = ["piotr"]
    run("task", "import", "-", input=json.dumps(tasks), env=env)
    ordered = sorted(json.loads(run("task", "export", env=env)), key=lambda t: t["id"])
    name = f"twoy-selection-test-{os.getpid()}"
    # A private server keeps the smoke run off Piotr's live tmux server.
    tmux = ("tmux", "-S", str(root / "tmux.sock"))
    pane = run(
        *tmux, "-f", "/dev/null", "new-session", "-d", "-P", "-F", "#{pane_id}", "-s", name,
        "-x", "120", "-y", "30", "env", f"TASKRC={rc}",
        f"TASKDATA={root / 'tasks'}", f"XDG_RUNTIME_DIR={runtime}",
        f"HOME={test_home}", f"HANDOFF_NAV_LOG={nav_log}",
        binary, "--report", "signal", "--data", str(root / "tui"),
    )
    try:
        run(*tmux, "set-option", "-p", "-t", pane, "remain-on-exit", "on")
        signal = runtime / "taskwarrior-tui" / f"selected-{pane.lstrip('%')}"

        def value():
            return signal.read_text() if signal.exists() else None

        # The TUI publishes "<uuid> <row>": the task and the screen row it was drawn on.
        def selected():
            line = value()
            return line.split()[0] if line else None

        def row():
            line = value()
            assert line and re.fullmatch(r"[0-9a-f-]{36} [0-9]+\n", line), f"signal format: {line!r}"
            return int(line.split()[1])

        def wait_for(predicate, label):
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline:
                if predicate():
                    print(f"PASS {label}")
                    return
                time.sleep(0.05)
            raise AssertionError(f"{label}: signal={value()!r}")

        def keys(*items):
            run(*tmux, "send-keys", "-t", pane, *items)

        first_id, second_id = (t["uuid"] for t in ordered[:2])
        first, second = first_id + "\n", second_id + "\n"
        wait_for(lambda: selected() == first_id, "initial UUID")
        first_row = row()
        assert signal.parent.stat().st_mode & 0o777 == 0o700
        before = signal.stat().st_mtime_ns
        time.sleep(0.3)
        assert signal.stat().st_mtime_ns == before, "unchanged selection rewrote signal"
        print("PASS private directory and no duplicate write")
        keys("S")
        wait_for(lambda: nav_log.exists() and nav_log.read_text() == first, "S queues piotr UUID once")
        assert selected() == first_id
        assert "start" not in json.loads(run("task", ordered[0]["uuid"], "export", env=env))[0]
        print("PASS S keeps selection and does not start task")
        keys("j")
        wait_for(lambda: selected() == second_id, "j selects second UUID")
        assert row() == first_row + 1, f"j moves the published row: {value()!r}"
        keys("S")
        time.sleep(0.3)
        assert nav_log.read_text() == first and selected() == second_id
        print("PASS S skips navigation on non-piotr row")
        keys("k")
        wait_for(lambda: selected() == first_id and row() == first_row, "k selects first UUID")
        if args.start_hook:
            keys("s")
            wait_for(lambda: nav_log.read_text() == first + f"start {first_id}\n", "s start hook opens handoff once")
            wait_for(lambda: "start" in json.loads(run("task", ordered[0]["uuid"], "export", env=env))[0], "s starts task")
            keys("s")
            wait_for(lambda: "start" not in json.loads(run("task", ordered[0]["uuid"], "export", env=env))[0], "s stops task")
            wait_for(lambda: nav_log.read_text() == first + f"start {first_id}\nstop {first_id}\n", "s stop hook closes handoff once")
        keys("J")
        wait_for(lambda: selected() not in (None, first_id, second_id), "paging changes UUID")
        keys("K")
        wait_for(lambda: selected() == first_id, "page up restores first UUID")
        target = ordered[39]
        keys("/", "C-u")
        run(*tmux, "send-keys", "-t", pane, "-l", f"status:pending description.is:{target['description']}")
        keys("Enter")
        wait_for(lambda: selected() == target["uuid"] and row() >= 0, "filter publishes matching UUID")
        run("task", target["uuid"], "done", env=env)
        keys("C-r")
        wait_for(lambda: value() is None, "refresh clears empty report selection")
        print(f"PASS all checks; artifacts: {root}")
    except BaseException:
        print(run(*tmux, "capture-pane", "-p", "-t", pane), file=sys.stderr)
        print(f"Failed test session: {name}; artifacts: {root}", file=sys.stderr)
        raise
    finally:
        subprocess.run([*tmux, "kill-server"], check=True)


if __name__ == "__main__":
    main()
