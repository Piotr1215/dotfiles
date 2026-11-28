#!/usr/bin/env bash
set -eo pipefail

# Render pending sudo requests, or refuse one after rechecking its state.
exec python3 - "$0" "$@" <<'PY'
import glob
import html
import json
import os
import shlex
import signal
import sys
import time

script, *args = sys.argv[1:]
pending = os.environ.get("SUDO_GATE_PENDING_DIR", "/run/sudo-agent-gate/pending")
comm = "sudo"
if os.environ.get("SUDO_GATE_TEST_MODE") == "1":
    comm = os.environ.get("SUDO_GATE_TEST_COMM", comm)
now = time.time()


def live(path):
    try:
        with open(path, encoding="utf-8") as source:
            record = json.load(source)
        pid, ts = record["sudo_pid"], record["ts"]
        if type(pid) is not int or pid <= 0 or type(ts) not in (int, float):
            return None
        if os.path.basename(path) != f"{pid}.json" or not 0 <= now - ts < 120:
            return None
        for key in ("command", "detection", "agent"):
            if not isinstance(record.get(key), str) or not record[key]:
                return None
        for key in ("cwd", "session", "pane"):
            if not isinstance(record.get(key), str) or not record[key].strip():
                record[key] = "unknown"
        with open(f"/proc/{pid}/comm", encoding="utf-8") as source:
            if source.read().strip() != comm:
                return None
        with open(f"/proc/{pid}/task/{pid}/children", encoding="utf-8") as source:
            if source.read().strip():
                return None
        return record
    except (OSError, ValueError, TypeError, KeyError):
        return None


def safe(value):
    return html.escape(str(value).replace("\n", " ").replace("\r", " "), quote=True).replace("|", "&#124;")


if args:
    if len(args) == 2 and args[0] == "--refuse" and args[1].isdigit():
        record = live(os.path.join(pending, f"{args[1]}.json"))
        if record:
            try:
                os.kill(record["sudo_pid"], signal.SIGTERM)
            except ProcessLookupError:
                pass
    sys.exit(0)

records = [record for path in sorted(glob.glob(os.path.join(pending, "*.json"))) if (record := live(path))]
if not records:
    print("---")
    sys.exit(0)

first = records[0]
label = f"🔑 ROOT {first['agent']}: {first['command']}"
if len(label) > 40:
    label = label[:39] + "…"
print(f"<span color='#ff4444'>{safe(label)}</span> | font=monospace")
print("---")
for index, record in enumerate(records):
    if index:
        print("---")
    for title, value in (("Command", record["command"]), ("Agent", record["agent"]),
                         ("Session / pane", f"{record['session']} / {record['pane']}"),
                         ("Cwd", record["cwd"]), ("Detection", record["detection"]),
                         ("Age", f"{int(now - record['ts'])}s")):
        print(f"{title}: {safe(value)} | font=monospace")
    print("Touch the YubiKey to run exactly this command. Do not tap for anything else while this is red. | font=monospace")
    command = shlex.quote(os.path.abspath(script)) + " --refuse " + str(record["sudo_pid"])
    print(f"Refuse | bash='{command}' terminal=false refresh=true")
PY
