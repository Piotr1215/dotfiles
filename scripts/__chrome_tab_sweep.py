#!/usr/bin/env python3
"""Native messaging host for the Tab sweep Chrome extension.

op "plan": given every open tab, name the ones to close: tabs whose GitHub
pull request is merged (one batched `gh api graphql` call, so private loft-sh
repos work through Piotr's gh login) and exact duplicate URLs, keeping one of
each. Pinned tabs are never closed. With "unattended": true (the extension's
background auto-close) a merged-PR tab in a live agent's tab group stays, and
the oldest copy of a duplicate stays.

op "report": DM Gordon (bus name "triage") the merged PRs the extension
closed, through ~/.claude/scripts/snd, only when the message carries
"report": true, which the extension sets while the popup's "Report closes to
Gordon" box is ticked (off by default; Piotr, 26 Nov: "this is mostly noise",
"either send all or don't", "report to gordon should only send closed prs not
other tabs"). Duplicate closes never reach Gordon.
"""
import importlib.util
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

MAX_MESSAGE = 8 * 1024 * 1024
MAX_TITLE = 200
PR_BATCH = 50
PR_RE = re.compile(r"^https://github\.com/([A-Za-z0-9-]+)/([A-Za-z0-9._-]+)/pull/([0-9]+)(?:[/?#]|$)")


def pr_key(url):
    """Return "owner/repo#number" for a GitHub pull request URL, else None."""
    match = PR_RE.match(url or "")
    return f"{match[1]}/{match[2]}#{match[3]}" if match else None


def merged_prs(keys):
    """Ask GitHub which of the given PR keys are merged.

    Returns (merged set, error list). A PR GitHub cannot resolve (deleted repo,
    no access) is simply not merged, so its tab stays open."""
    gh = os.environ.get("TAB_SWEEP_GH") or shutil.which("gh") or "gh"
    keys = sorted(keys)
    merged, errors = set(), []
    for start in range(0, len(keys), PR_BATCH):
        batch = keys[start:start + PR_BATCH]
        fields = []
        for i, key in enumerate(batch):
            repo, number = key.split("#")
            owner, name = repo.split("/")
            # Safe to inline: PR_RE allows no quotes or braces in these parts.
            fields.append(f'p{i}: repository(owner: "{owner}", name: "{name}") {{ pullRequest(number: {number}) {{ merged }} }}')
        try:
            run = subprocess.run([gh, "api", "graphql", "-f", "query=query { " + " ".join(fields) + " }"],
                                 capture_output=True, text=True, timeout=30)
            data = json.loads(run.stdout or "{}").get("data") or {}
        except (OSError, subprocess.TimeoutExpired, ValueError) as exc:
            errors.append(f"gh: {exc}")
            continue
        if not data:
            errors.append("gh: " + (run.stderr.strip() or "no data")[:300])
        for i, key in enumerate(batch):
            if ((data.get(f"p{i}") or {}).get("pullRequest") or {}).get("merged"):
                merged.add(key)
    return merged, errors


def grouped(tab):
    """True for a tab inside a Chrome tab group (groupId -1 means none)."""
    return isinstance(tab.get("groupId"), int) and tab["groupId"] >= 0


def agent_groups(tabs, groups):
    """The tab groups among `groups` that hold a tab a live Claude agent drives.

    The Claude tab-owner hook maps each tab an agent touches to its tmux pane,
    read here through __chrome_agent_tmux.py. A group with no such tab, like
    the "handoffs" group the handoff board opens for Piotr, is not an agent's.
    If the map cannot be read, every group counts as an agent's."""
    if not groups:
        return set()
    try:
        spec = importlib.util.spec_from_file_location("agent_tabs", Path(__file__).resolve().with_name("__chrome_agent_tmux.py"))
        owners = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(owners)
        mapped = owners.load_tabs()
    except Exception:
        return set(groups)
    live = set()
    for tab in tabs:
        group = tab.get("groupId")
        if group in groups and group not in live and tab["id"] in mapped and owners.live_pane(mapped[tab["id"]][1]):
            live.add(group)
    return live


def plan(tabs, unattended=False):
    """Pick the tabs to close: merged PRs first, then extra copies of a URL.

    A duplicate group keeps a pinned copy, else one in a tab group, else the
    active one, else the first by window and position. A tab in a tab group is
    never closed as a duplicate: agents work in their own groups (Claude in
    Chrome tracks each tab by id), so an agent's copy stays and Piotr's
    ungrouped copy closes. Each duplicate row names the copy it keeps.

    unattended is a sweep nobody clicked. It keeps a merged-PR tab in a live
    agent's group, so an agent reading a merged PR keeps its tab, while one in
    a group no agent drives (the handoffs group) closes. Among duplicates it
    keeps the oldest copy (lowest tab id) over the active one: reopening a
    link closes the fresh tab, not an older one holding unsaved typing."""
    tabs = [t for t in tabs if isinstance(t, dict) and isinstance(t.get("id"), int) and t.get("url")]
    merged, errors = merged_prs({k for k in map(pr_key, (t["url"] for t in tabs)) if k})
    candidates = [t for t in tabs if pr_key(t["url"]) in merged and not t.get("pinned")]
    spared = agent_groups(tabs, {t["groupId"] for t in candidates if grouped(t)}) if unattended else set()
    close = {}
    for tab in candidates:
        if not (grouped(tab) and tab["groupId"] in spared):
            close[tab["id"]] = {"reason": "merged", "pr": pr_key(tab["url"])}
    groups = {}
    for tab in tabs:
        groups.setdefault(tab["url"], []).append(tab)
    for copies in groups.values():
        if len(copies) < 2:
            continue
        order = (lambda t: (t["id"],)) if unattended else (lambda t: (not t.get("active"), t.get("windowId", 0), t.get("index", 0)))
        copies.sort(key=lambda t: (not t.get("pinned"), not grouped(t), *order(t)))
        for tab in copies[1:]:
            if not tab.get("pinned") and not grouped(tab) and tab["id"] not in close:
                close[tab["id"]] = {"reason": "duplicate", "kept": copies[0]["id"]}
    rows = [{"id": t["id"], "url": t["url"], "title": str(t.get("title") or "")[:MAX_TITLE], **close[t["id"]]}
            for t in tabs if t["id"] in close]
    rows.sort(key=lambda r: (r["reason"] != "merged", r.get("pr") or r["url"]))
    return {"close": rows, "tabs": len(tabs), "prs": len({pr_key(t["url"]) for t in tabs} - {None}), "errors": errors}


def report_text(prs):
    """One bus line naming the merged PRs whose tabs the sweep closed."""
    return (f"Chrome tab sweep closed the tabs of {len(prs)} merged PR{'s' * (len(prs) != 1)}: "
            + ", ".join(prs[:20]) + (f", and {len(prs) - 20} more" if len(prs) > 20 else "") + ".")


def report(closed):
    """DM triage the merged PRs among the closed rows; True when snd published it.

    Closed duplicates are left out, and with no merged PR nothing is sent."""
    prs = sorted({r["pr"] for r in closed if isinstance(r, dict) and r.get("reason") == "merged" and isinstance(r.get("pr"), str)})
    if not prs:
        return {"reported": False}
    snd = os.environ.get("TAB_SWEEP_SND") or os.path.expanduser("~/.claude/scripts/snd")
    env = {**os.environ, "SND_FROM": "tab-sweep"}
    try:
        run = subprocess.run([snd, "--no-human", "-t", os.environ.get("TAB_SWEEP_TO") or "triage", report_text(prs)],
                             stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20, env=env)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"reported": False, "error": str(exc)}
    return {"reported": run.returncode == 0, **({} if run.returncode == 0 else {"error": (run.stderr.strip() or f"snd exit {run.returncode}")[:300]})}


def handle(message):
    """Dispatch one request from the extension."""
    if message.get("op") == "plan":
        return plan(message.get("tabs") or [], unattended=message.get("unattended") is True)
    if message.get("op") == "report":
        if message.get("report") is not True:
            return {"reported": False}
        return report(message.get("closed") or [])
    return {"error": "unknown op"}


def main():
    header = sys.stdin.buffer.read(4)
    if len(header) != 4:
        return
    length = struct.unpack("=I", header)[0]
    payload = sys.stdin.buffer.read(length) if length <= MAX_MESSAGE else b""
    try:
        message = json.loads(payload)
        reply = handle(message) if isinstance(message, dict) else {"error": "bad message"}
    except ValueError:
        reply = {"error": "bad message"}
    data = json.dumps(reply).encode()
    sys.stdout.buffer.write(struct.pack("=I", len(data)) + data)
    sys.stdout.buffer.flush()


if __name__ == "__main__":
    main()
