#!/usr/bin/env python3
"""Print every link in a tmux pane's scrollback, newest first, one per line.

Feeds the M-u picker (__tmux_pane_urls.sh). Alacritty hints only reach what is
on screen; this reads the whole history with capture-pane -J, so a link that
wrapped is joined back and a link scrolled off is still there. It also reads
the escape sequences (-e), which carry OSC 8 hyperlinks: text such as "PR #7"
whose target is a URL the screen never shows.

Usage: __tmux_pane_urls.py <pane_id>
"""
import re
import subprocess
import sys

OSC8 = re.compile(r"\x1b\]8;[^;\x07\x1b]*;([^\x07\x1b]+)(?:\x07|\x1b\\)")
ESCAPES = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[@-_]")
URL = re.compile(r"\b(?:https?|ftp|file)://[^\s<>\"'`\\\x00-\x1f]+")
TRAILING = ".,;:!?'\"*_"
PAIRS = {")": "(", "]": "[", "}": "{"}


def trim(url):
    """Drop prose punctuation and closing brackets the URL never opened."""
    while url:
        last = url[-1]
        if last in TRAILING:
            url = url[:-1]
        elif last in PAIRS and url.count(last) > url.count(PAIRS[last]):
            url = url[:-1]
        else:
            break
    return url


def truncated(raw):
    """True when a display cut the link short: Claude's collapsed tool view
    prints "https://githu…", and trimming the dots off "…/os..." would leave a
    link that looks whole and is not."""
    url = trim(raw)
    return "\u2026" in raw or raw[len(url):].startswith("...")


def extract_urls(text):
    """Return the links in text, the last seen first, each once."""
    found = []
    for line in text.splitlines():
        # Claude Code links URL-looking text itself, so an OSC 8 target can be
        # as cut short or punctuated as the text it wraps.
        raw = OSC8.findall(line) + URL.findall(ESCAPES.sub("", line))
        found.extend(trim(m) for m in raw if not truncated(m))
    seen = set()
    ordered = []
    for url in reversed(found):
        if "://" in url and url not in seen:
            seen.add(url)
            ordered.append(url)
    return ordered


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 1
    text = subprocess.run(
        ["tmux", "capture-pane", "-p", "-e", "-J", "-S", "-", "-t", sys.argv[1]],
        capture_output=True, text=True, errors="replace", check=True,
    ).stdout
    for url in extract_urls(text):
        print(url)
    return 0


if __name__ == "__main__":
    sys.exit(main())
