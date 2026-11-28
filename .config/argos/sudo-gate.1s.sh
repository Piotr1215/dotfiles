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
import subprocess
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

# While a request waits the pane Piotr looks at turns dark red, and its border bright red.
ALERT_STYLES = (("window-active-style", "bg=#4a0000"), ("pane-active-border-style", "fg=#ff4444,bg=default"))


def tmux_cue(text):
    """Show a waiting request in tmux, where Piotr looks, and undo it when it ends.

    Piotr, 28 Nov: "I look all the time in the middle of the screen (where you input
    box is)" and "top right wouldn't rebbister well", so the panel alone went unseen.
    @sudo_gate feeds the red block beside the centred window tab (.tmux.conf), and
    ALERT_STYLES tint the active pane; the styles in force before are saved in the state
    file and set back once the request ends. tmux runs only when the text changes; when
    it fails the state file is left as it was, so the next second tries again.
    """
    test = os.environ.get("SUDO_GATE_TEST_MODE") == "1"
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    path = (os.environ.get("SUDO_GATE_CUE_STATE") if test else None) or os.path.join(runtime, "sudo-gate-tmux-cue.json")
    tmux = (os.environ.get("SUDO_GATE_TMUX") if test else None) or "/usr/local/bin/tmux"
    text = "".join(ch for ch in text if ch.isprintable())[:160]
    try:
        with open(path, encoding="utf-8") as handle:
            state = json.load(handle)
        if not isinstance(state, dict) or not isinstance(state.get("saved"), dict):
            raise ValueError("bad cue state")
    except (OSError, ValueError):
        state = {"text": None, "saved": {}}
    if state["text"] == text:
        return
    saved = {k: v for k, v in state["saved"].items() if isinstance(k, str) and isinstance(v, str)}
    try:
        args = [tmux, "set", "-g", "@sudo_gate", text]
        if text:
            if not saved:
                for name, _ in ALERT_STYLES:
                    shown = subprocess.run([tmux, "show", "-gwv", name], timeout=2, capture_output=True, text=True, check=True)
                    saved[name] = shown.stdout.strip()
            for name, value in ALERT_STYLES:
                args += [";", "set", "-gw", name, value]
        else:
            for name, value in saved.items():
                args += [";", "set", "-gw", name, value]
            saved = {}
        subprocess.run(args, timeout=2, capture_output=True, check=True)
        clients = subprocess.run([tmux, "list-clients", "-F", "#{client_name}"], timeout=2, capture_output=True, text=True).stdout.split()
        for client in clients:
            subprocess.run([tmux, "refresh-client", "-S", "-t", client], timeout=2, capture_output=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({"text": text, "saved": saved}, handle)
    except (OSError, subprocess.SubprocessError):
        pass


records, unknown, _ = scan()
size = os.environ.get("SUDO_GATE_PANEL_SIZE", "12")
size = size if size.replace(".", "", 1).isdigit() else "12"
if unknown:
    print(f"<tt><span color='#ff4444'>🔑 ROOT state unavailable</span></tt> | font='monospace' size={size}")
elif records:
    first = records[0]
    label = f"ROOT {first['agent']}: {first['command']}"
    if len(label) > 40:
        label = label[:39] + "…"
    # Same shape as SU:0, C:OK and R:30: a plain prefix, then the coloured part. A label
    # coloured from its first character rendered white on the panel (screenshot, 28 Nov
    # 15:08 and 15:10: #F2F2F2). Red text alone still went unseen (Piotr, 28 Nov: "it
    # simply doens't draw my attention enough"), so it flashes a red block each second.
    tick = int(os.environ.get("SUDO_GATE_TEST_NOW", "0")) if os.environ.get("SUDO_GATE_TEST_MODE") == "1" else int(now)
    style = "background='#ff4444' color='#ffffff'" if tick % 2 == 0 else "color='#ff4444'"
    print(f"<tt><b>SU:</b></tt><tt><span {style}> {safe(label)} </span></tt> | font='monospace' size={size}")
else:
    # Idle reads like the other labels (C:OK, K:3) at their size: the old small grey
    # key was there but too faint to find (Piotr, 28 Nov: "I still don't see argos").
    print(f"<tt><b>SU:</b></tt><tt><span color='#888888'>0</span></tt> | font='monospace' size={size}")
sys.stdout.flush()
if unknown:
    tmux_cue("ROOT request state unavailable: do not touch the YubiKey")
elif records:
    # Any agent can rewrite a tmux option, so the cue says only "look now"; the command
    # to judge is in the SU menu, read from the gate's root-owned records.
    tmux_cue("AGENT ROOT REQUEST: check the SU menu, top right, before touching the YubiKey")
else:
    tmux_cue("")
print("---")
if unknown:
    print("<b>Root request state unavailable</b> | color=#ff4444")
    print("Do not touch the YubiKey.")
# Three rows decide a request: who wants what, how to allow, how to refuse. The rest sits
# under Details (Piotr, 28 Nov: "it has no ryhme or structure", "I don't understand what
# I'm looiking for", "I don't need 80% of things there").
for index, record in enumerate(records):
    if index:
        print("---")
    print(f"<b>{safe(record['agent'])} wants root:</b> {safe(record['command'])} | font=monospace")
    if not unknown:
        print("Touch the YubiKey to allow it")
    command = shlex.quote(os.path.abspath(script)) + " --refuse " + str(record["sudo_pid"])
    print(f"<b>✕ Refuse</b> | bash='{command}' terminal=false refresh=true color=#ff4444")
    print("Details")
    for title, value in (("Command", record["command"]), ("Agent", record["agent"]),
                         ("Session / pane", f"{record['session']} / {record['pane']}"),
                         ("Cwd", record["cwd"]), ("Detection", record["detection"]),
                         ("Age", f"{max(0, int(now - record['ts']))}s")):
        print(f"--{title}: {safe(value)} | font=monospace")
    program = record.get("program")
    if isinstance(program, str) and program:
        pid = record["sudo_pid"]
        gate = "sudo -n /usr/local/sbin/sudo-agent-gate"
        print(f"--Always allow {safe(os.path.basename(program))} for agents, from the next call | bash='{gate} allow-program-from {pid}' terminal=false refresh=true")
        print(f"--Always allow exactly this command, from the next call | bash='{gate} allow-exact-from {pid}' terminal=false refresh=true")

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

if records or unknown:
    print("---")
# The list itself lives in a root-owned file Piotr edits, not in this menu
# (Piotr, 28 Nov: "I need file that I can edit that contains this list").
edit = os.path.normpath(os.path.join(os.path.dirname(os.path.realpath(script)), "../../scripts/__sudo_gate_allow_edit.sh"))
print(f"Edit allowed commands | bash='/usr/local/bin/tmux new-window -n sudo-allow {edit}' terminal=false")
recent = os.environ.get("SUDO_GATE_RECENT_FILE", "/run/sudo-agent-gate/recent.jsonl")
recent_items = list(jsonlines(recent))[-5:]
if recent_items:
    print("Recently auto-allowed")
for item in recent_items:
    print(f"--{safe(item.get('agent', 'unknown'))}: {safe(item.get('command', ''))} | font=monospace")
PY
