#!/usr/bin/env python3
"""Emit link picker candidates as "display<TAB>command" lines.

Two sources feed the picker: the curated pet link snippets file, and recent
browser history from every LibreWolf and Chrome profile on this machine.
__link_pane_runner.sh pipes this into fzf with --with-nth=1, so the first
column is what gets displayed and searched, and the second is the command
that gets run on selection.

Environment:
  PET_SNIPPET_FILE       pet links toml (default ~/dev/pet-snippets/pet-links.toml)
  LINK_HISTORY           set to 0 to drop the history rows entirely
  LINK_HISTORY_LIMIT     how many history rows to keep (default 500)
  LINK_HISTORY_PER_HOST  cap per host, keeps github off the whole list (default 30)
  LINK_HISTORY_DBS       colon separated paths or globs, replaces the defaults
"""

import glob
import os
import re
import shlex
import shutil
import sqlite3
import sys
import tempfile
import tomllib
from collections import Counter
from urllib.parse import urlsplit

SNIPPET_FILE = os.environ.get(
    "PET_SNIPPET_FILE", os.path.expanduser("~/dev/pet-snippets/pet-links.toml")
)
HISTORY_ENABLED = os.environ.get("LINK_HISTORY", "1") != "0"
HISTORY_LIMIT = int(os.environ.get("LINK_HISTORY_LIMIT", "500"))
PER_HOST_LIMIT = int(os.environ.get("LINK_HISTORY_PER_HOST", "30"))

DEFAULT_DB_GLOBS = [
    "~/.var/app/io.gitlab.librewolf-community/.librewolf/*/places.sqlite",
    "~/.librewolf/*/places.sqlite",
    "~/.mozilla/firefox/*/places.sqlite",
    "~/.config/google-chrome/*/History",
]

# last_visit_date is microseconds since the unix epoch
FIREFOX_QUERY = """
    select url, title, last_visit_date / 1000000.0
    from moz_places
    where title is not null and title != '' and last_visit_date is not null
      and url like 'http%'
    order by last_visit_date desc limit ?
"""

# last_visit_time is microseconds since 1601-01-01
CHROME_QUERY = """
    select url, title, last_visit_time / 1000000.0 - 11644473600
    from urls
    where title is not null and title != '' and last_visit_time > 0
      and url like 'http%'
    order by last_visit_time desc limit ?
"""

TITLE_WIDTH = 68
URL_WIDTH = 95

# Search engines and login redirects: every row is a dead end in a link picker.
NOISE_HOSTS = frozenset(
    [
        "duckduckgo.com",
        "www.duckduckgo.com",
        "html.duckduckgo.com",
        "lite.duckduckgo.com",
        "google.com",
        "www.google.com",
        "accounts.google.com",
        "www.bing.com",
        "search.brave.com",
        "login.microsoftonline.com",
    ]
)

NOTION_HOSTS = ("notion.so", "notion.com")
NOTION_PAGE_ID = re.compile(r"[0-9a-f]{32}")
UNREAD_BADGE = re.compile(r"^\(\d+\)\s*")
XDG_OPEN_URL = re.compile(r'\s*xdg-open\s+"?([^"\s]+)')


# Strip the noise a browser tab title carries: the unread counter Notion and
# Gmail prepend, and the trailing app name.
def clean_title(title):
    title = UNREAD_BADGE.sub("", title.strip())
    if title.endswith("| Notion"):
        title = title[: -len("| Notion")].strip()
    return " ".join(title.split())


# One key per page, so the same Notion doc reached under different query
# strings, or under both notion.so and app.notion.com, collapses into a single
# hit instead of a screenful of them.
def dedupe_key(url):
    parts = urlsplit(url)
    host = parts.netloc.lower()
    if host.endswith(NOTION_HOSTS):
        page_id = NOTION_PAGE_ID.search(parts.path)
        if page_id:
            return "notion:" + page_id.group(0)
    key = host + parts.path.rstrip("/")
    if parts.query:
        key += "?" + parts.query
    return key.lower()


# Snippet commands carry shell escapes (\# and \~ in anchors); undo them for
# display only. The command itself is passed through untouched.
def url_from_command(command):
    found = XDG_OPEN_URL.match(command)
    return found.group(1).replace("\\", "") if found else ""


def render(title, url, tag, command):
    if len(title) > TITLE_WIDTH:
        title = title[: TITLE_WIDTH - 3] + "..."
    if len(url) > URL_WIDTH:
        url = url[: URL_WIDTH - 3] + "..."
    display = "%-*s  %-*s  %s" % (
        TITLE_WIDTH + 2,
        "[" + title + "]",
        URL_WIDTH,
        url,
        tag,
    )
    return display.rstrip() + "\t" + command


def load_snippets():
    try:
        with open(SNIPPET_FILE, "rb") as handle:
            data = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as err:
        print("link candidates: %s: %s" % (SNIPPET_FILE, err), file=sys.stderr)
        return []

    snippets = data.get("Snippets") or data.get("snippets") or []
    rows = []
    for entry in snippets:
        command = entry.get("command") or entry.get("Command") or ""
        title = entry.get("Description") or entry.get("description") or ""
        if not command:
            continue
        if title.startswith("Link to "):
            title = title[len("Link to ") :]
        rows.append((title.strip(), command, url_from_command(command)))
    rows.sort(key=lambda row: row[0].casefold())
    return rows


def history_dbs():
    override = os.environ.get("LINK_HISTORY_DBS")
    patterns = override.split(":") if override else DEFAULT_DB_GLOBS
    paths = []
    for pattern in patterns:
        paths.extend(sorted(glob.glob(os.path.expanduser(pattern))))
    return paths


# The live databases are locked while the browser runs, so work on a copy.
# The write ahead log holds the newest visits, so it has to come along.
def read_db(path, workdir, index, limit):
    copy = os.path.join(workdir, "%d.db" % index)
    shutil.copy(path, copy)
    for suffix in ("-wal", "-shm"):
        if os.path.exists(path + suffix):
            shutil.copy(path + suffix, copy + suffix)

    conn = sqlite3.connect(copy)
    try:
        tables = conn.execute(
            "select name from sqlite_master where type = 'table'"
        ).fetchall()
        names = {row[0] for row in tables}
        if "moz_places" in names:
            query = FIREFOX_QUERY
        elif "urls" in names:
            query = CHROME_QUERY
        else:
            return []
        return conn.execute(query, (limit,)).fetchall()
    finally:
        conn.close()


def load_history(seen):
    rows = []
    with tempfile.TemporaryDirectory(prefix="link-history-") as workdir:
        for index, path in enumerate(history_dbs()):
            try:
                rows.extend(read_db(path, workdir, index, HISTORY_LIMIT * 4))
            except (OSError, sqlite3.Error) as err:
                print("link candidates: %s: %s" % (path, err), file=sys.stderr)

    rows.sort(key=lambda row: row[2], reverse=True)
    hits = []
    per_host = Counter()
    for url, title, _ in rows:
        host = urlsplit(url).netloc.lower()
        if host in NOISE_HOSTS:
            continue
        # A day of github reviewing would otherwise fill the whole budget and
        # push every other host out of the picker.
        if per_host[host] >= PER_HOST_LIMIT:
            continue
        key = dedupe_key(url)
        if key in seen:
            continue
        title = clean_title(title)
        if not title or title == url:
            continue
        # Same page under a different path (a PR and its /changes tab) shares a
        # title, so this collapses what the url key cannot.
        title_key = (host, title.casefold())
        if title_key in seen:
            continue
        seen.add(key)
        seen.add(title_key)
        per_host[host] += 1
        hits.append((title, url))
        if len(hits) >= HISTORY_LIMIT:
            break
    return hits


def main():
    lines = []
    seen = set()
    for title, command, url in load_snippets():
        seen.add(dedupe_key(url) if url else command)
        lines.append(render(title, url, "#link", command))

    if HISTORY_ENABLED:
        for title, url in load_history(seen):
            command = "xdg-open " + shlex.quote(url)
            lines.append(render(title, url, "#history", command))

    if lines:
        sys.stdout.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
