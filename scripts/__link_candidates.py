#!/usr/bin/env python3
"""Emit link picker candidates as "display<TAB>command" lines.

Two sources feed the picker: recent browser history from the LibreWolf and
Chrome profiles named in the conf, and the curated pet link snippets file.
History comes first, grouped by profile in conf order and newest first inside
each group; the snippets follow, alphabetically.
__link_pane_runner.sh pipes this into fzf with --with-nth=1, so the first
column is what gets displayed and searched, and the second is the command
that gets run on selection.

Settings live in __link_picker.conf, because the picker runs from a global
hotkey and that process carries none of the shell environment. The variables
below still win when they are set, for one-off runs from a terminal.

Environment:
  PET_SNIPPET_FILE       pet links toml (default ~/dev/pet-snippets/pet-links.toml)
  LINK_PICKER_CONF       settings file (default ~/dev/dotfiles/scripts/__link_picker.conf)
  LINK_HISTORY           set to 0 to drop the history rows entirely
  LINK_HISTORY_LIMIT     how many history rows to keep (default 500)
  LINK_HISTORY_PER_HOST  cap per host per profile, keeps github off the whole list
  LINK_HISTORY_DBS       colon separated paths or globs, replaces the conf profiles
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
CONF_FILE = os.environ.get(
    "LINK_PICKER_CONF",
    os.path.expanduser("~/dev/dotfiles/scripts/__link_picker.conf"),
)

# Used when the conf file names no profiles: every profile on the machine,
# under one tag, which is the behaviour before the work/home split existed.
DEFAULT_DB_GLOBS = [
    "~/.var/app/io.gitlab.librewolf-community/.librewolf/*/places.sqlite",
    "~/.librewolf/*/places.sqlite",
    "~/.mozilla/firefox/*/places.sqlite",
    "~/.config/google-chrome/*/History",
]
DEFAULT_TAG = "history"

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
OFF_VALUES = frozenset(["0", "off", "no", "false"])
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


# "key = value", full line comments only. A repeated "profile" key accumulates,
# which is how one tag can cover several browser profiles.
def load_conf():
    settings = {}
    profiles = []
    try:
        with open(CONF_FILE) as handle:
            text = handle.read()
    except OSError:
        return settings, profiles

    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key, value = key.strip().lower(), value.strip()
        if key == "profile":
            tag, _, path = value.partition(":")
            if tag.strip() and path.strip():
                profiles.append((tag.strip(), os.path.expanduser(path.strip())))
        else:
            settings[key] = value
    return settings, profiles


def setting(env_name, conf_key, default, conf):
    return os.environ.get(env_name) or conf.get(conf_key) or default


# Yields (tag, path) so every row can carry the profile it came from.
def history_dbs(profiles):
    override = os.environ.get("LINK_HISTORY_DBS")
    if override:
        sources = [(DEFAULT_TAG, pattern) for pattern in override.split(":")]
    elif profiles:
        sources = profiles
    else:
        sources = [(DEFAULT_TAG, pattern) for pattern in DEFAULT_DB_GLOBS]

    found = []
    for tag, pattern in sources:
        for path in sorted(glob.glob(os.path.expanduser(pattern))):
            found.append((tag, path))
    return found


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


def load_history(seen, profiles, limit, per_host_limit):
    sources = history_dbs(profiles)
    # The order profiles are listed in the conf is the order their rows appear
    # in, so work sits above home. Ranking the tag rather than hardcoding
    # "work" keeps the conf the only place that decides.
    tag_order = {}
    for tag, _ in sources:
        tag_order.setdefault(tag, len(tag_order))

    rows = []
    with tempfile.TemporaryDirectory(prefix="link-history-") as workdir:
        for index, (tag, path) in enumerate(sources):
            try:
                for url, title, when in read_db(path, workdir, index, limit * 4):
                    rows.append((url, title, when, tag))
            except (OSError, sqlite3.Error) as err:
                print("link candidates: %s: %s" % (path, err), file=sys.stderr)

    rows.sort(key=lambda row: row[2], reverse=True)
    hits = []
    per_host = Counter()
    for url, title, _, tag in rows:
        host = urlsplit(url).netloc.lower()
        if host in NOISE_HOSTS:
            continue
        # A day of github reviewing would otherwise fill the whole budget and
        # push every other host out of the picker. Counted per profile, so work
        # github and home github do not compete for the same slots.
        if per_host[(tag, host)] >= per_host_limit:
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
        per_host[(tag, host)] += 1
        hits.append((title, url, tag))
        if len(hits) >= limit:
            break
    # Group the survivors by profile for display only. Which rows survive is
    # still decided newest-first across every profile, so a heavy work day
    # cannot spend the whole budget before home is looked at. The sort is
    # stable, so recency still orders the rows inside each group.
    hits.sort(key=lambda hit: tag_order.get(hit[2], len(tag_order)))
    return hits


def main():
    conf, profiles = load_conf()
    history_on = setting("LINK_HISTORY", "history", "on", conf).lower() not in OFF_VALUES
    limit = int(setting("LINK_HISTORY_LIMIT", "limit", "500", conf))
    per_host_limit = int(setting("LINK_HISTORY_PER_HOST", "per_host", "30", conf))

    # Snippets are resolved first whatever the display order, because they seed
    # the dedupe: a bookmarked url then keeps its curated title instead of
    # coming back a second time under whatever the browser tab was called.
    seen = set()
    snippets = []
    for title, command, url in load_snippets():
        seen.add(dedupe_key(url) if url else command)
        snippets.append(render(title, url, "#link", command))

    # History leads, because the picker is reached for to get back to a page
    # from earlier today. The bookmarks are the long tail you search for by
    # name, so they sit underneath.
    lines = []
    if history_on:
        for title, url, tag in load_history(seen, profiles, limit, per_host_limit):
            command = "xdg-open " + shlex.quote(url)
            lines.append(render(title, url, "#" + tag, command))
    lines.extend(snippets)

    if lines:
        sys.stdout.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
