#!/usr/bin/env python3
"""Native messaging host for the Tab sweep Chrome extension.

op "plan": given every open tab, name the ones to close: tabs whose GitHub
pull request is merged (one batched `gh api graphql` call, so private loft-sh
repos work through Piotr's gh login) and exact duplicate URLs, keeping one of
each. Pinned tabs are never closed.

op "report": DM Gordon (bus name "triage") what the extension closed, through
~/.claude/scripts/snd, only when the message carries "report": true, which the
extension sets while the popup's "Report closes to Gordon" box is ticked (off
by default; Piotr, 26 Nov: "this is mostly noise", "either send all or don't").
"""
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from urllib.parse import urlsplit

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


def plan(tabs):
    """Pick the tabs to close: merged PRs first, then extra copies of a URL.

    A duplicate group keeps a pinned copy, else one in a tab group, else the
    active one, else the first by window and position. A tab in a tab group is
    never closed as a duplicate: agents work in their own groups (Claude in
    Chrome tracks each tab by id), so an agent's copy stays and Piotr's
    ungrouped copy closes."""
    tabs = [t for t in tabs if isinstance(t, dict) and isinstance(t.get("id"), int) and t.get("url")]
    merged, errors = merged_prs({k for k in map(pr_key, (t["url"] for t in tabs)) if k})
    close = {}
    for tab in tabs:
        key = pr_key(tab["url"])
        if key in merged and not tab.get("pinned"):
            close[tab["id"]] = {"reason": "merged", "pr": key}
    groups = {}
    for tab in tabs:
        groups.setdefault(tab["url"], []).append(tab)
    for copies in groups.values():
        if len(copies) < 2:
            continue
        copies.sort(key=lambda t: (not t.get("pinned"), not grouped(t), not t.get("active"), t.get("windowId", 0), t.get("index", 0)))
        for tab in copies[1:]:
            if not tab.get("pinned") and not grouped(tab) and tab["id"] not in close:
                close[tab["id"]] = {"reason": "duplicate"}
    rows = [{"id": t["id"], "url": t["url"], "title": str(t.get("title") or "")[:MAX_TITLE], **close[t["id"]]}
            for t in tabs if t["id"] in close]
    rows.sort(key=lambda r: (r["reason"] != "merged", r.get("pr") or r["url"]))
    return {"close": rows, "tabs": len(tabs), "prs": len({pr_key(t["url"]) for t in tabs} - {None}), "errors": errors}


def short_url(url):
    """URL without query or fragment, so a token in a query string stays off the bus."""
    parts = urlsplit(url)
    return f"{parts.scheme}://{parts.netloc}{parts.path}" if parts.netloc else url.split("?")[0].split("#")[0]


def report_text(closed):
    """One bus line naming what the sweep closed."""
    prs = sorted({r["pr"] for r in closed if r.get("reason") == "merged" and r.get("pr")})
    dupes = {}
    for row in closed:
        if row.get("reason") == "duplicate":
            url = short_url(row.get("url", ""))
            dupes[url] = dupes.get(url, 0) + 1
    parts = [f"Chrome tab sweep closed {len(closed)} tab{'s' * (len(closed) != 1)}."]
    if prs:
        parts.append(f"Merged PRs ({len(prs)}): " + ", ".join(prs[:20]) + (f", and {len(prs) - 20} more" if len(prs) > 20 else "") + ".")
    if dupes:
        listed = [u + (f" x{n}" if n > 1 else "") for u, n in sorted(dupes.items())]
        parts.append(f"Duplicates ({sum(dupes.values())}): " + ", ".join(listed[:10]) + (f", and {len(listed) - 10} more" if len(listed) > 10 else "") + ".")
    return " ".join(parts)


def report(closed):
    """DM the report to triage; True when snd published it."""
    rows = [r for r in closed if isinstance(r, dict)]
    if not rows:
        return {"reported": False, "error": "nothing closed"}
    snd = os.environ.get("TAB_SWEEP_SND") or os.path.expanduser("~/.claude/scripts/snd")
    env = {**os.environ, "SND_FROM": "tab-sweep"}
    try:
        run = subprocess.run([snd, "--no-human", "-t", os.environ.get("TAB_SWEEP_TO") or "triage", report_text(rows)],
                             stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20, env=env)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"reported": False, "error": str(exc)}
    return {"reported": run.returncode == 0, **({} if run.returncode == 0 else {"error": (run.stderr.strip() or f"snd exit {run.returncode}")[:300]})}


def handle(message):
    """Dispatch one request from the extension."""
    if message.get("op") == "plan":
        return plan(message.get("tabs") or [])
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
