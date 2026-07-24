#!/usr/bin/env python3
# PROJECT: desktop-notifications
# Durable notification log for the GNOME session (where dunst cannot run because
# GNOME Shell owns org.freedesktop.Notifications). Eavesdrops the session bus for
# Notify method calls and appends one tab-separated line per notification to
# ~/.local/state/notifications.log:
#
#     2026-07-24 10:35:05<TAB>app<TAB>summary<TAB>body
#
# Why: GNOME popups vanish on click and can't be copied or screenshotted, and
# GNOME has no notification-history CLI. This makes every notification durable
# (copy/paste to share) and machine-readable (tools can tail the file).
#
# Runs as the notification-logger.service user unit. dbus-monitor delivers each
# matched message twice on this dbus build, so an identical (app,summary,body)
# within DEDUP_WINDOW seconds is collapsed to one line.
import os
import re
import subprocess
import sys
import time
from datetime import datetime

LOG = os.path.expanduser("~/.local/state/notifications.log")
MAX_BYTES = 512 * 1024   # trim once the log grows past this...
KEEP_LINES = 1000        # ...down to this many most-recent lines
DEDUP_WINDOW = 2.0       # seconds; collapse identical back-to-back repeats

STR_RE = re.compile(r'^\s*string "(.*)"\s*$')


def clean(s):
    return s.replace("\t", " ").replace("\n", "\\n")


def trim_if_big():
    try:
        if os.path.getsize(LOG) <= MAX_BYTES:
            return
        with open(LOG) as f:
            lines = f.readlines()
        with open(LOG, "w") as f:
            f.writelines(lines[-KEEP_LINES:])
    except OSError:
        pass


def main():
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    proc = subprocess.Popen(
        ["dbus-monitor", "--session",
         "interface='org.freedesktop.Notifications',member='Notify'"],
        stdout=subprocess.PIPE, text=True, bufsize=1,
    )
    if proc.stdout is None:
        return 1

    last = None       # last emitted (app, summary, body)
    last_t = 0.0
    in_notify = False
    strings = []

    for line in proc.stdout:
        if "member=Notify" in line:
            in_notify, strings = True, []
            continue
        if not in_notify:
            continue
        m = STR_RE.match(line)
        if m:
            strings.append(m.group(1))
            if len(strings) >= 4:          # app_name, app_icon, summary, body
                app, summary, body = strings[0], strings[2], strings[3]
                rec = (app, summary, body)
                now = time.monotonic()
                in_notify = False
                if rec == last and (now - last_t) < DEDUP_WINDOW:
                    continue               # dbus double or rapid duplicate
                last, last_t = rec, now
                ts = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S")
                with open(LOG, "a") as f:
                    f.write(f"{ts}\t{clean(app)}\t{clean(summary)}\t{clean(body)}\n")
                trim_if_big()
        elif line.lstrip().startswith(("array", "int32")):
            in_notify = False              # no body field: give up on this one

    return proc.wait() or 1                # dbus-monitor died; let systemd restart


if __name__ == "__main__":
    sys.exit(main())
