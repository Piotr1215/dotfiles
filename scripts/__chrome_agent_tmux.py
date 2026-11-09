#!/usr/bin/env python3
"""Native messaging host for switching the sole attached tmux client."""
import json
import os
import re
import struct
import subprocess
import sys
import time

MAX_MESSAGE = 4096
MAX_NAME_TABS = 200
MAX_LOG = 256 * 1024
PANE_RE = re.compile(r"^%[0-9]+$")


def run_tmux(*args):
    command = ["tmux"]
    socket = os.environ.get("AGENT_TMUX_TEST_SOCKET")
    if socket:
        command += ["-L", socket, "-f", "/dev/null"]
    return subprocess.run(command + list(args), text=True, capture_output=True, check=False)


def tabs_file():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(base, "agent-tabs", "tabs.jsonl")


def owner_name(row):
    """The recorded @agent_name, else the tmux session; None when neither is usable."""
    for key in ("agent", "session"):
        name = row.get(key)
        if isinstance(name, str):
            name = name.strip()
            if name and len(name) <= 64 and name.isprintable():
                return name
    return None


def load_tabs():
    """Newest line per tab_id wins; later lines win ts ties. Values are (ts, pane, name)."""
    latest = {}
    try:
        with open(tabs_file(), encoding="utf-8") as handle:
            for line in handle:
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                tab = row.get("tab_id") if isinstance(row, dict) else None
                pane = row.get("pane") if isinstance(row, dict) else None
                ts = row.get("ts")
                if type(tab) is not int or not isinstance(pane, str) or not PANE_RE.match(pane):
                    continue
                ts = ts if type(ts) in (int, float) else 0
                if tab not in latest or ts >= latest[tab][0]:
                    latest[tab] = (ts, pane, owner_name(row))
    except OSError:
        return {}
    return latest


def live_pane(pane):
    result = run_tmux("display", "-p", "-t", pane, "#{pane_id}")
    return result.returncode == 0 and result.stdout.strip() == pane


def sole_client():
    clients = run_tmux("list-clients", "-F", "#{client_tty}")
    attached = clients.stdout.splitlines() if clients.returncode == 0 else []
    return attached[0] if len(attached) == 1 else None


def switch_to_pane(client, pane):
    # switch-client with a pane target selects its session, window and pane.
    return run_tmux("switch-client", "-c", client, "-t", pane).returncode == 0


def find_pane(message):
    tabs = load_tabs()
    tab_id = message.get("tabId")
    if type(tab_id) is int and tab_id in tabs and live_pane(tabs[tab_id][1]):
        return tabs[tab_id][1], "tab_id"
    siblings = message.get("groupTabIds")
    if isinstance(siblings, list):
        found = [tabs[t] for t in siblings if type(t) is int and t in tabs]
        for _, pane, _ in sorted(found, key=lambda row: row[0], reverse=True):
            if live_pane(pane):
                return pane, "group_sibling"
    return None, None


def title_match(message):
    owner = message.get("owner")
    if not isinstance(owner, str) or not owner or len(owner) > 200 or any(c in owner for c in "\n\r\0"):
        return None
    panes = run_tmux("list-panes", "-a", "-F", "#{session_name}\t#{@agent_name}")
    if panes.returncode or f"{owner}\t{owner}" not in panes.stdout.splitlines():
        return None
    return "=" + owner


def tab_names(message):
    """Map tab ids to owning agent names for retitling "Claude" groups; never touches tmux."""
    ids = message.get("tabIds")
    if not isinstance(ids, list):
        return {"names": {}}
    tabs = load_tabs()
    names = {}
    for tab in ids[:MAX_NAME_TABS]:
        if type(tab) is int and tab in tabs and tabs[tab][2]:
            names[str(tab)] = tabs[tab][2]
    return {"names": names}


def handle(message):
    if not isinstance(message, dict):
        return {"switched": False}
    if message.get("op") == "names":
        return tab_names(message)
    target, rule = find_pane(message)
    if target is None:
        target = title_match(message)
        rule = "title" if target else None
    if target is None:
        return {"switched": False}
    client = sole_client()
    if client is None:
        return {"switched": False}
    if not switch_to_pane(client, target):
        return {"switched": False}
    return {"switched": True, "rule": rule}


def log_call(payload, reply):
    """Append what Chrome sent and what the host did to agent-tabs/host.log.

    Without it a click that does not switch leaves no trace: Chrome drops the
    reply. A miss also records how many tmux clients were attached, since the
    host switches only with exactly one. The log rolls to host.log.1 past 256 KB."""
    try:
        path = os.path.join(os.path.dirname(tabs_file()), "host.log")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if os.path.exists(path) and os.path.getsize(path) > MAX_LOG:
            os.replace(path, path + ".1")
        row = {"ts": int(time.time()), "in": payload.decode("utf-8", "replace")[:600], "out": reply}
        if not reply.get("switched"):
            clients = run_tmux("list-clients", "-F", "#{client_tty}")
            row["clients"] = len(clients.stdout.splitlines()) if clients.returncode == 0 else None
        with open(path, "a", encoding="utf-8") as handle_:
            handle_.write(json.dumps(row) + "\n")
    except Exception:  # logging must never break a switch
        pass


def main():
    header = sys.stdin.buffer.read(4)
    if len(header) != 4:
        return
    length = struct.unpack("=I", header)[0]
    if length > MAX_MESSAGE:
        return
    payload = sys.stdin.buffer.read(length)
    if len(payload) != length:
        return
    try:
        reply = handle(json.loads(payload))
    except (ValueError, OSError):
        reply = {"switched": False}
    data = json.dumps(reply).encode()
    sys.stdout.buffer.write(struct.pack("=I", len(data)) + data)
    sys.stdout.buffer.flush()
    log_call(payload, reply)


if __name__ == "__main__":
    main()
