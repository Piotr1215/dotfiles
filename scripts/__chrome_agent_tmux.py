#!/usr/bin/env python3
"""Native messaging host for switching the sole attached tmux client."""
import json
import os
import re
import shutil
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


def title_name(owner):
    """The agent name in a group title, without the status symbol Claude in Chrome puts in front."""
    if not isinstance(owner, str) or len(owner) > 200 or any(c in owner for c in "\n\r\0\t"):
        return None
    start = 0
    while start < len(owner) and not owner[start].isalnum():
        start += 1
    return owner[start:].strip() or None


def title_match(message):
    """The pane whose @agent_name is the group title: the agent's own session first, else the only one.

    Codex titles its group with the agent name; the extension renames a Claude
    group to "✅<agent>", which keeps working when the tab map is stale (a
    Chrome restart gives every tab a new id) or the agent restarted in a new pane."""
    name = title_name(message.get("owner"))
    if name is None:
        return None
    panes = run_tmux("list-panes", "-a", "-F", "#{pane_id}\t#{session_name}\t#{@agent_name}")
    if panes.returncode:
        return None
    found = []
    for line in panes.stdout.splitlines():
        pane, _, rest = line.partition("\t")
        session, _, agent = rest.partition("\t")
        if agent == name and PANE_RE.match(pane):
            found.append((session, pane))
    own = [pane for session, pane in found if session == name]
    if own:
        return own[0]
    return found[0][1] if len(found) == 1 else None


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


def extension_dir():
    return os.environ.get("AGENT_TAB_EXTENSION_DIR") or os.path.join(
        os.path.dirname(os.path.dirname(os.path.realpath(__file__))), ".config", "chrome-agent-tmux")


def check_extension():
    """Whether the extension folder would load, so the extension reloads itself only into code that runs.

    Chrome refuses a folder holding a name that starts with "_" and leaves no
    extension running (9 Nov), and a service worker with a syntax error never
    starts, which would also end the self-reload."""
    folder = extension_dir()
    problems = []
    for root, dirs, files in os.walk(folder):
        for name in dirs + files:
            if name.startswith("_"):
                problems.append("reserved name " + os.path.relpath(os.path.join(root, name), folder))
    try:
        with open(os.path.join(folder, "manifest.json"), encoding="utf-8") as handle_:
            worker = json.load(handle_)["background"]["service_worker"]
        if not isinstance(worker, str) or not os.path.isfile(os.path.join(folder, worker)):
            raise ValueError(f"no service worker file {worker!r}")
    except (OSError, ValueError, KeyError, TypeError) as error:
        problems.append(f"manifest: {error}")
        worker = None
    if worker:
        node = shutil.which("node")
        if node is None:
            problems.append("node not found for the syntax check")
        else:
            try:
                result = subprocess.run([node, "--check", os.path.join(folder, worker)],
                                        capture_output=True, text=True, timeout=20, check=False)
            except (OSError, subprocess.SubprocessError) as error:
                problems.append(f"syntax check: {error}")
            else:
                if result.returncode:
                    lines = [line for line in result.stderr.splitlines() if "Error" in line] or ["syntax error"]
                    problems.append(f"{worker}: {lines[0]}")
    if problems:
        return {"loadable": False, "error": "; ".join(problems)[:300]}
    return {"loadable": True}


def handle(message):
    if not isinstance(message, dict):
        return {"switched": False}
    if message.get("op") == "names":
        return tab_names(message)
    if message.get("op") == "check":
        return check_extension()
    if message.get("op") == "loaded":
        # The extension reports each start after a reload, so host.log shows when a change went live.
        return {"ok": True}
    if message.get("owner") == "handoffs":
        panes = run_tmux("list-panes", "-a", "-F", "#{pane_id}\t#{@agent_name}")
        matches = [pane for line in panes.stdout.splitlines()
                   for pane, sep, agent in [line.partition("\t")]
                   if sep and agent == "triage" and PANE_RE.fullmatch(pane)] if panes.returncode == 0 else []
        target = matches[0] if len(matches) == 1 else None
        rule = "handoffs" if target else None
    else:
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
