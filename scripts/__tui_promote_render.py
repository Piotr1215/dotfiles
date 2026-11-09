#!/usr/bin/env python3
"""Render a Taskwarrior handoff as Linear issue fields for __tui_promote_handoff.sh.

Reads `task export` JSON (a one-element array) on stdin and prints one JSON object:
{"title", "description", "priority", "security"}. Pure: no network, no task writes.

Why: DEVOPS-1862 was promoted with a capitalised title, raw `what:`/`done-when:`
fields, Gordon-to-Piotr phrasing, no command, no source links and no priority.
"""
import json
import os
import re
import sys

PRIORITY = {"H": 2, "M": 3, "L": 4}  # Linear: 0 none, 1 urgent, 2 high, 3 medium, 4 low
INTERNAL = ("trace", "brief-updated", "brief-update", "kind", "proof", "log", "prep",
            "prep-result", "prep-blocker", "prep-dependency", "route", "leftovers", "draft",
            "piotr-comment", "pr-watch", "want-reply")
URL = re.compile(r"https?://[^\s<>()\[\]`\"']+")
SOURCE_HOST = re.compile(r"^https://([a-z0-9-]+\.)?(slack\.com|github\.com)/", re.I)
# Sentences that speak from Gordon to Piotr have no place in a shared issue.
ADDRESSED = re.compile(r"\b(yours to|your step|your call|for you to|you need to|you can run)\b", re.I)
SECURITY = re.compile(r"\b(cve|security)\b", re.I)


def field(text):
    m = re.match(r"^([a-z][a-z-]*):\s*(.*)$", text, re.S | re.I)
    return (m.group(1).lower(), m.group(2).strip()) if m else (None, text.strip())


def clean_url(url):
    # A trailing colon or period after a bare URL turns into a broken Linear link.
    return url.rstrip(".,:;!?")


def neutral(text):
    sentences = re.split(r"(?<=[.!?])\s+", text.strip())
    return " ".join(s for s in sentences if s and not ADDRESSED.search(s)).strip()


def brief_text(task, annotations):
    path = next((v for k, v in annotations if k == "trace"), "")
    if not path:
        root = os.environ.get("TASK_BRIEFS_DIR", os.path.expanduser("~/.local/state/taskwarrior/briefs"))
        path = os.path.join(root, task.get("uuid", ""), "brief.md")
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return ""


def brief_sections(text):
    sections, name = {}, None
    for line in text.splitlines():
        if line.startswith("## "):
            name = line[3:].strip().lower()
            sections[name] = []
        elif name:
            sections[name].append(line)
    return {k: "\n".join(v) for k, v in sections.items()}


def render(task):
    notes = sorted(task.get("annotations") or [], key=lambda a: a.get("entry", ""))
    annotations = [field(a.get("description", "")) for a in notes]
    title = (task.get("description") or "").strip().lower()
    what = next((v for k, v in annotations if k == "what"), "") or next((v for k, v in annotations if k == "brief"), "")
    done = next((v for k, v in annotations if k == "done-when"), "")
    cmds = [v for k, v in annotations if k == "cmd" and v]
    sections = brief_sections(brief_text(task, annotations))

    links = []
    def add(url):
        url = clean_url(url)
        if url and url not in links:
            links.append(url)
    for key, value in annotations:
        if key in INTERNAL or key == "cmd":
            continue
        for url in URL.findall(value):
            if key in ("link", "target", "source", "slack", "pr-url") or SOURCE_HOST.match(url):
                add(url)
    for name in ("brief", "target", "links", "link", "source", "sources"):
        for url in URL.findall(sections.get(name, "")):
            if name != "brief" or SOURCE_HOST.match(url):
                add(url)

    parts = []
    if what:
        parts.append(neutral(what))
    if links:
        parts.append("Sources:\n" + "\n".join(f"- {u}" for u in links))
    if cmds:
        parts.append("Command:\n\n```sh\n" + cmds[-1] + "\n```")
    if done:
        parts.append("Done when: " + done)
    description = "\n\n".join(p for p in parts if p) if (what or done) else ""

    haystack = " ".join([task.get("description") or "", " ".join(task.get("tags") or []),
                         " ".join(v for k, v in annotations if k not in INTERNAL),
                         sections.get("what", ""), sections.get("brief", "")])
    return {
        "title": title,
        "description": description,
        "priority": PRIORITY.get((task.get("priority") or "").upper(), 0),
        "security": bool(SECURITY.search(haystack)),
    }


def main():
    data = json.load(sys.stdin)
    if not isinstance(data, list) or len(data) != 1:
        sys.exit("task not found")
    out = render(data[0])
    if not out["title"]:
        sys.exit("handoff has no title")
    if not out["description"]:
        sys.exit("handoff has no brief")
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
