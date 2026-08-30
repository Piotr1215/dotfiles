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

# A string field opens with `string "` and closes on the line whose last
# character is the quote. dbus-monitor prints an embedded newline literally, so
# a multi-line body spans several output lines and only the last one closes it.
STR_RE = re.compile(r'^\s*string "(.*)$')


def clean(s):
    return s.replace("\t", " ").replace("\n", "\\n")


def closed(text):
    """Return the string body if this line closes it, else None."""
    stripped = text.rstrip()
    return stripped[:-1] if stripped.endswith('"') else None


def parse(lines):
    """Yield (app, summary, body) for every Notify call in dbus-monitor output."""
    in_notify = False
    strings = []
    pending = None      # body of a string still waiting for its closing quote

    for line in lines:
        if "member=Notify" in line:
            in_notify, strings, pending = True, [], None
            continue
        if not in_notify:
            continue
        raw = line.rstrip("\n")
        if pending is not None:
            tail = closed(raw)
            if tail is None:
                pending += "\n" + raw
                continue
            value = pending + "\n" + tail
            pending = None
        else:
            match = STR_RE.match(raw)
            if not match:
                if raw.lstrip().startswith(("array", "int32")):
                    in_notify = False      # no body field: give up on this one
                continue
            value = closed(match.group(1))
            if value is None:
                pending = match.group(1)   # string carries on to the next line
                continue
        strings.append(value)
        if len(strings) >= 4:              # app_name, app_icon, summary, body
            in_notify = False
            yield strings[0], strings[2], strings[3]


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

    for rec in parse(proc.stdout):
        now = time.monotonic()
        if rec == last and (now - last_t) < DEDUP_WINDOW:
            continue                       # dbus double or rapid duplicate
        last, last_t = rec, now
        app, summary, body = rec
        ts = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S")
        with open(LOG, "a") as f:
            f.write(f"{ts}\t{clean(app)}\t{clean(summary)}\t{clean(body)}\n")
        trim_if_big()

    return proc.wait() or 1                # dbus-monitor died; let systemd restart


if __name__ == "__main__":
    sys.exit(main())
