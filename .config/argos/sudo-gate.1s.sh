#!/usr/bin/env bash
set -eo pipefail

# Render pending sudo requests, or refuse one after rechecking its state.
# Same label size as the other panel labels (see panel_label_size).
SUDO_GATE_PANEL_SIZE=12
# shellcheck source=/dev/null
if source "$HOME/dev/dotfiles/scripts/__lib_screen.sh" 2>/dev/null; then
    SUDO_GATE_PANEL_SIZE=$(panel_label_size 12) || SUDO_GATE_PANEL_SIZE=12
fi
export SUDO_GATE_PANEL_SIZE
exec python3 - "$0" "$@" <<'PY'
import html
import json
import math
import os
import shlex
import signal
import sys
import time

script, *args = sys.argv[1:]
pending = os.environ.get("SUDO_GATE_PENDING_DIR", "/run/sudo-agent-gate/pending")
comm = "sudo"
proc_root = "/proc"
if os.environ.get("SUDO_GATE_TEST_MODE") == "1":
    comm = os.environ.get("SUDO_GATE_TEST_COMM", comm)
    proc_root = os.environ.get("SUDO_GATE_TEST_PROC_ROOT", proc_root)
now = time.time()


def pid_exists(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OverflowError as error:
        raise ValueError("invalid pid") from error


def live(path, strict=False):
    try:
        with open(path, encoding="utf-8") as source:
            record = json.load(source)
        pid, ts = record["sudo_pid"], record["ts"]
        if type(pid) is not int or pid <= 0 or type(ts) not in (int, float) or not math.isfinite(ts):
            raise ValueError("invalid pid or timestamp")
        if os.path.basename(path) != f"{pid}.json":
            raise ValueError("invalid filename")
        for key in ("command", "detection", "agent"):
            if not isinstance(record.get(key), str) or not record[key]:
                raise ValueError("invalid request")
        start = record.get("start_time")
        if start is None:
            if not 0 <= now - ts < 120:
                return None
        else:
            if not isinstance(start, str) or not start.isdigit():
                raise ValueError("invalid process start")
            with open(f"{proc_root}/{pid}/stat", encoding="utf-8") as source:
                actual = source.read().rsplit(")", 1)[1].split()[19]
            if start != actual:
                return None
        for key in ("cwd", "session", "pane"):
            if not isinstance(record.get(key), str) or not record[key].strip():
                record[key] = "unknown"
        with open(f"{proc_root}/{pid}/comm", encoding="utf-8") as source:
            if source.read().strip() != comm:
                return None
        with open(f"{proc_root}/{pid}/task/{pid}/children", encoding="utf-8") as source:
            children = source.read().split()
        for child in children:
            try:
                with open(f"{proc_root}/{child}/cmdline", "rb") as source:
                    command = source.read().split(b"\0")
            except FileNotFoundError:
                # A vanished child is safe only once the process is gone.
                if strict and pid_exists(int(child)):
                    raise
                continue
            if not any(command):
                # A just-exited gate helper can be a zombie until sudo reaps it.
                continue
            if not any(arg == b"/usr/local/sbin/sudo-agent-gate" or
                       (os.environ.get("SUDO_GATE_TEST_MODE") == "1" and
                        arg.endswith(b"/__sudo_agent_gate.py")) for arg in command):
                return None
        return record
    except FileNotFoundError:
        if strict:
            name = os.path.basename(path).removesuffix(".json")
            if not name.isdigit() or int(name) <= 0 or pid_exists(int(name)):
                raise
        return None
    except (OSError, ValueError, TypeError, KeyError, IndexError):
        if strict:
            raise
        return None


def safe(value):
    return html.escape(str(value).replace("\n", " ").replace("\r", " "), quote=True).replace("|", "&#124;")


def scan():
    try:
        with os.scandir(pending) as entries:
            paths = sorted(entry.path for entry in entries if entry.name.endswith(".json"))
    except FileNotFoundError:
        return [], False, False
    except OSError:
        return [], True, False
    records = []
    unknown = False
    for path in paths:
        try:
            record = live(path, strict=True)
            if record:
                records.append(record)
        except (OSError, ValueError, TypeError, KeyError, IndexError):
            unknown = True
    return records, unknown, bool(paths)


if args:
    if args in (["--busy"], ["--state-present"]):
        records, unknown, present = scan()
        if args == ["--state-present"]:
            sys.exit(2 if unknown else 0 if present else 1)
        sys.exit(2 if unknown else 0 if records else 1)
    if len(args) == 2 and args[0] == "--refuse" and args[1].isdigit():
        record = live(os.path.join(pending, f"{args[1]}.json"))
        if record:
            try:
                os.kill(record["sudo_pid"], signal.SIGTERM)
            except ProcessLookupError:
                pass
    sys.exit(0)

records, unknown, _ = scan()
size = os.environ.get("SUDO_GATE_PANEL_SIZE", "12")
size = size if size.replace(".", "", 1).isdigit() else "12"
if unknown:
    print(f"<span color='#ff4444'>🔑 ROOT state unavailable</span> | font=monospace size={size}")
elif records:
    first = records[0]
    label = f"🔑 ROOT {first['agent']}: {first['command']}"
    if len(label) > 40:
        label = label[:39] + "…"
    print(f"<span color='#ff4444'>{safe(label)}</span> | font=monospace size={size}")
else:
    # Idle reads like the other labels (C:OK, K:3) at their size: the old small grey
    # key was there but too faint to find (Piotr, 28 Nov: "I still don't see argos").
    print(f"<tt><b>SU:</b></tt><tt><span color='#888888'>0</span></tt> | font='monospace' size={size}")
if unknown:
    print("---")
    print("Root request state unavailable. Do not touch the YubiKey. | font=monospace")
print("---")
for index, record in enumerate(records):
    if index:
        print("---")
    for title, value in (("Command", record["command"]), ("Agent", record["agent"]),
                         ("Session / pane", f"{record['session']} / {record['pane']}"),
                         ("Cwd", record["cwd"]), ("Detection", record["detection"]),
                         ("Age", f"{max(0, int(now - record['ts']))}s")):
        print(f"{title}: {safe(value)} | font=monospace")
    if not unknown:
        print("Touch the YubiKey to run exactly this command. Do not tap for anything else while this is red. | font=monospace")
    command = shlex.quote(os.path.abspath(script)) + " --refuse " + str(record["sudo_pid"])
    print(f"Refuse | bash='{command}' terminal=false refresh=true")

    program = record.get("program")
    if isinstance(program, str) and program:
        pid = record["sudo_pid"]
        gate = "sudo -n /usr/local/sbin/sudo-agent-gate"
        print(f"Always allow {safe(os.path.basename(program))} for agents | bash='{gate} allow-program-from {pid}' terminal=false refresh=true")
        print(f"Always allow exactly this command | bash='{gate} allow-exact-from {pid}' terminal=false refresh=true")
        print("Applies from the next call; touch or refuse this one. | font=monospace")

def jsonlines(path):
    try:
        with open(path, encoding="utf-8") as source:
            for line in source:
                try:
                    value = json.loads(line)
                    if isinstance(value, dict):
                        yield value
                except ValueError:
                    continue
    except OSError:
        pass

if records:
    print("---")
# The list itself lives in a root-owned file Piotr edits, not in this menu
# (Piotr, 28 Nov: "I need file that I can edit that contains this list").
edit = os.path.normpath(os.path.join(os.path.dirname(os.path.realpath(script)), "../../scripts/__sudo_gate_allow_edit.sh"))
print(f"Edit allowed commands | bash='/usr/local/bin/tmux new-window -n sudo-allow {edit}' terminal=false")
recent = os.environ.get("SUDO_GATE_RECENT_FILE", "/run/sudo-agent-gate/recent.jsonl")
for item in list(jsonlines(recent))[-5:]:
    print(f"auto-allowed: {safe(item.get('agent', 'unknown'))} {safe(item.get('command', ''))} | font=monospace")
PY
