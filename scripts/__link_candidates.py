#!/usr/bin/env python3
"""Emit link picker candidates as "display<TAB>command<TAB>title<TAB>url" lines.

Two sources feed the picker: recent browser history from the LibreWolf and
Chrome profiles named in the conf, and the curated pet link snippets file.
Pinned rows come first, then history grouped by profile in conf order and
newest first inside each group, then the snippets alphabetically.
__link_pane_runner.sh pipes this into fzf with --with-nth=1, so the first
column is what gets displayed, and the second is the command that gets run on
selection. The trailing title and url columns are hidden too: they are what
ctrl-f writes to the pins file, untruncated.

With --query the picker stops being a list fzf filters and becomes a search.
fzf runs --disabled and reloads this script on every keystroke, so the ranking
in __lib_vimium_rank.py decides what comes back and in what order, over a
corpus far wider than the list above: every history row in every profile, plus
the browser's own bookmarks, not the recent few hundred. Vimium C's omnibox
found pages this picker could not, and this is why.

The corpus is cached, because rebuilding it per keystroke means copying a
hundred megabytes of locked sqlite. The cache is rebuilt when a source database
has moved on and the cache is older than the ttl. Pins and snippets are always
read live, so a ctrl-f pin shows up on the next keystroke.

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
  LINK_PINS_FILE         pinned rows (default ~/.local/state/link-picker/pins)
  LINK_CORPUS_FILE       search corpus cache (default ~/.local/state/link-picker/corpus)
  LINK_CORPUS_TTL        seconds before the cache may be rebuilt (default 300)
  LINK_SEARCH_LIMIT      how many ranked rows to return (default 200)
  LINK_BOOKMARKS         set to 0 to drop browser bookmarks from the corpus

Subcommands:
  --toggle-pin <line>    pin or unpin the row, called from the ctrl-f binding
  --query <string>       ranked search; an empty string gives the default list
"""

import glob
import json
import os
import re
import shlex
import shutil
import signal
import sqlite3
import sys
import tempfile
import time
import tomllib
from collections import Counter
from urllib.parse import urlsplit

# Run as a script, so sys.path already carries this directory; the insert is
# for the case where something imports this file by path instead.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import __lib_vimium_rank as vimium  # noqa: E402

SNIPPET_FILE = os.environ.get(
    "PET_SNIPPET_FILE", os.path.expanduser("~/dev/pet-snippets/pet-links.toml")
)
CONF_FILE = os.environ.get(
    "LINK_PICKER_CONF",
    os.path.expanduser("~/dev/dotfiles/scripts/__link_picker.conf"),
)

# Pins are user state that changes on every ctrl-f, so they live outside the
# dotfiles tree: a file in the repo would leave the working tree permanently
# dirty, and the working tree is what cron and stow read.
DEFAULT_PINS_FILE = "~/.local/state/link-picker/pins"

# The search corpus is derived state, so it sits next to the pins rather than
# in the repo, for the same reason.
DEFAULT_CORPUS_FILE = "~/.local/state/link-picker/corpus"

# A running browser touches its history write ahead log constantly, so mtime
# alone would rebuild the corpus on every keystroke. This is the floor between
# rebuilds; within it the picker searches whatever it already has.
DEFAULT_CORPUS_TTL = "300"

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

# The same rows without the recency window, for the search corpus. A page from
# five weeks ago is exactly what the picker could not reach before.
FIREFOX_ALL_QUERY = FIREFOX_QUERY.replace("order by last_visit_date desc limit ?", "")
CHROME_ALL_QUERY = CHROME_QUERY.replace("order by last_visit_time desc limit ?", "")

# A bookmark's own title is what was typed when it was saved, so it beats the
# page title; the page title is the fallback for a bookmark saved unnamed.
FIREFOX_BOOKMARK_QUERY = """
    select place.url, coalesce(nullif(mark.title, ''), place.title)
    from moz_bookmarks mark join moz_places place on mark.fk = place.id
    where mark.type = 1 and place.url like 'http%'
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


def render(title, url, tag, command, pinned=False):
    raw_title, raw_url = " ".join(title.split()), url
    if len(title) > TITLE_WIDTH:
        title = title[: TITLE_WIDTH - 3] + "..."
    if len(url) > URL_WIDTH:
        url = url[: URL_WIDTH - 3] + "..."
    display = "%s %-*s  %-*s  %s" % (
        "*" if pinned else " ",
        TITLE_WIDTH + 2,
        "[" + title + "]",
        URL_WIDTH,
        url,
        tag,
    )
    return "\t".join([display.rstrip(), command, raw_title, raw_url])


# What makes two rows the same link. A snippet may run something that is not
# xdg-open at all, and then the command itself is the only identity it has.
def pin_key(url, command):
    return dedupe_key(url) if url else command


def pins_path(conf):
    return os.path.expanduser(setting("LINK_PINS_FILE", "pins", DEFAULT_PINS_FILE, conf))


# A pin stores the whole row, url, title and command, rather than a reference
# into history. A page pinned today drops out of the history window within the
# week, and a pin that quietly stops appearing is worse than no pin.
def load_pins(path):
    pins = []
    try:
        with open(path) as handle:
            text = handle.read()
    except OSError:
        return pins
    for line in text.splitlines():
        fields = line.split("\t")
        if len(fields) == 3 and fields[2]:
            pins.append((fields[0], fields[1], fields[2]))
    return pins


def save_pins(path, pins):
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w") as handle:
        for pin in pins:
            handle.write("\t".join(pin) + "\n")


# Called from the ctrl-f binding with the whole picker line, hidden columns
# included, which is where the untruncated title and url come from.
def toggle_pin(path, line):
    fields = line.split("\t")
    if len(fields) < 4:
        return
    command, title, url = fields[1], fields[2], fields[3]
    key = pin_key(url, command)
    pins = load_pins(path)
    kept = [pin for pin in pins if pin_key(pin[0], pin[2]) != key]
    if len(kept) == len(pins):
        kept.append((url, title, command))
    save_pins(path, kept)


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
def copy_db(path, workdir, index):
    copy = os.path.join(workdir, "%d.db" % index)
    shutil.copy(path, copy)
    for suffix in ("-wal", "-shm"):
        if os.path.exists(path + suffix):
            shutil.copy(path + suffix, copy + suffix)
    return copy


def db_flavour(conn):
    tables = conn.execute("select name from sqlite_master where type = 'table'")
    names = {row[0] for row in tables}
    if "moz_places" in names:
        return "firefox"
    if "urls" in names:
        return "chrome"
    return ""


def read_db(path, workdir, index, limit):
    conn = sqlite3.connect(copy_db(path, workdir, index))
    try:
        flavour = db_flavour(conn)
        if not flavour:
            return []
        query = FIREFOX_QUERY if flavour == "firefox" else CHROME_QUERY
        return conn.execute(query, (limit,)).fetchall()
    finally:
        conn.close()


# Every history row, and every bookmark the same profile holds. Chrome keeps
# its bookmarks in a json file beside the history database rather than in it.
def read_db_corpus(path, workdir, index, bookmarks_on):
    conn = sqlite3.connect(copy_db(path, workdir, index))
    try:
        flavour = db_flavour(conn)
        if not flavour:
            return [], []
        query = FIREFOX_ALL_QUERY if flavour == "firefox" else CHROME_ALL_QUERY
        history = conn.execute(query).fetchall()
        marks = []
        if not bookmarks_on:
            return history, marks
        if flavour == "chrome":
            return history, read_chrome_bookmarks(
                os.path.join(os.path.dirname(path), "Bookmarks")
            )
        try:
            marks = conn.execute(FIREFOX_BOOKMARK_QUERY).fetchall()
        except sqlite3.Error:
            # A places file without the bookmark tables still has history worth
            # having, so this cannot be allowed to take the profile with it.
            pass
        return history, marks
    finally:
        conn.close()


def read_chrome_bookmarks(path):
    try:
        with open(path) as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return []

    rows = []
    stack = [root for root in data.get("roots", {}).values() if isinstance(root, dict)]
    while stack:
        node = stack.pop()
        if node.get("type") == "url" and str(node.get("url", "")).startswith("http"):
            rows.append((node["url"], node.get("name") or ""))
        stack.extend(child for child in node.get("children", ()) if isinstance(child, dict))
    return rows


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


def corpus_path(conf):
    return os.path.expanduser(
        setting("LINK_CORPUS_FILE", "corpus", DEFAULT_CORPUS_FILE, conf)
    )


# Which files decide whether the cache has fallen behind. The write ahead log
# holds visits the database file does not know about yet, and Chrome keeps its
# bookmarks beside the history rather than inside it.
def corpus_sources(source):
    return [source, source + "-wal", os.path.join(os.path.dirname(source), "Bookmarks")]


# Rebuild only once a profile has moved on and the ttl has run out. A browser
# rewrites its log every few seconds, so mtime alone would put a hundred
# megabytes of sqlite copying on every keystroke.
def corpus_stale(path, sources, ttl):
    try:
        written = os.stat(path).st_mtime
    except OSError:
        return True
    if time.time() - written < ttl:
        return False
    for _, source in sources:
        for candidate in corpus_sources(source):
            try:
                if os.stat(candidate).st_mtime > written:
                    return True
            except OSError:
                continue
    return False


# Tabs and newlines are the row format, so they cannot survive in a field.
def flatten(value):
    return value.replace("\t", " ").replace("\r", " ").replace("\n", " ")


def build_corpus(path, sources, bookmarks_on):
    rows = []
    with tempfile.TemporaryDirectory(prefix="link-corpus-") as workdir:
        for index, (tag, source) in enumerate(sources):
            try:
                history, marks = read_db_corpus(source, workdir, index, bookmarks_on)
            except (OSError, sqlite3.Error) as err:
                print("link candidates: %s: %s" % (source, err), file=sys.stderr)
                continue
            for url, title, when in history:
                rows.append(("h", tag, when or 0, url, title or ""))
            for url, title in marks:
                rows.append(("b", tag, 0, url, title or ""))

    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    # Written aside and renamed, so a picker reading the cache while another
    # rebuilds it never reads half a file.
    scratch = "%s.%d" % (path, os.getpid())
    try:
        with open(scratch, "w") as handle:
            for kind, tag, when, url, title in rows:
                handle.write(
                    "%s\t%s\t%.0f\t%s\t%s\n"
                    % (kind, tag, when, flatten(url), flatten(title))
                )
        os.replace(scratch, path)
    except OSError as err:
        print("link candidates: %s: %s" % (path, err), file=sys.stderr)
    return rows


def load_corpus(conf, profiles):
    path = corpus_path(conf)
    sources = history_dbs(profiles)
    ttl = float(setting("LINK_CORPUS_TTL", "corpus_ttl", DEFAULT_CORPUS_TTL, conf))
    bookmarks_on = (
        setting("LINK_BOOKMARKS", "bookmarks", "on", conf).lower() not in OFF_VALUES
    )
    if corpus_stale(path, sources, ttl):
        return build_corpus(path, sources, bookmarks_on)

    rows = []
    try:
        with open(path) as handle:
            for line in handle:
                fields = line.rstrip("\n").split("\t")
                if len(fields) == 5:
                    rows.append(
                        (fields[0], fields[1], float(fields[2]), fields[3], fields[4])
                    )
    except (OSError, ValueError):
        return build_corpus(path, sources, bookmarks_on)
    return rows


# A leading # is a filter on the source rather than a search term, which is how
# #pin, #link, #mark, #work and #home narrow what gets ranked.
def parse_query(query):
    terms, tags = [], set()
    for token in query.split():
        if token.startswith("#") and len(token) > 1:
            tags.add(token[1:].lower())
        else:
            terms.append(token)
    return terms, tags


def default_lines(conf, profiles, tags=()):
    history_on = setting("LINK_HISTORY", "history", "on", conf).lower() not in OFF_VALUES
    limit = int(setting("LINK_HISTORY_LIMIT", "limit", "500", conf))
    per_host_limit = int(setting("LINK_HISTORY_PER_HOST", "per_host", "30", conf))

    # Pins are resolved first and sit at the very top, above even the newest
    # history: a pin is the one row whose position you chose by hand.
    seen = set()
    pinned = set()
    rows = []
    for url, title, command in load_pins(pins_path(conf)):
        pinned.add(pin_key(url, command))
        seen.add(pin_key(url, command))
        if url:
            seen.add((urlsplit(url).netloc.lower(), title.casefold()))
        rows.append(("pin", render(title, url, "#pin", command, pinned=True)))

    # Snippets are resolved before history whatever the display order, because
    # they seed the dedupe: a bookmarked url then keeps its curated title
    # instead of coming back under whatever the browser tab was called.
    # Only a pin removes a bookmark from this block, never another bookmark.
    # Two snippets can point at one url under different descriptions, which is
    # two ways to recall the same page, and both are worth keeping searchable.
    snippets = []
    for title, command, url in load_snippets():
        key = pin_key(url, command)
        seen.add(key)
        if key in pinned:
            continue
        snippets.append(("link", render(title, url, "#link", command)))

    # History next, because the picker is reached for to get back to a page
    # from earlier today. The bookmarks are the long tail you search for by
    # name, so they sit underneath.
    if history_on:
        for title, url, tag in load_history(seen, profiles, limit, per_host_limit):
            command = "xdg-open " + shlex.quote(url)
            rows.append((tag, render(title, url, "#" + tag, command)))
    rows.extend(snippets)

    if tags:
        rows = [row for row in rows if row[0] in tags]
    return [line for _, line in rows]


# The search path. fzf does no matching of its own here, so what comes back and
# in what order is entirely this function and __lib_vimium_rank.
def run_search(conf, profiles, query):
    terms, tags = parse_query(query)
    if not terms:
        return default_lines(conf, profiles, tags)

    limit = int(setting("LINK_SEARCH_LIMIT", "results", "200", conf))
    history_on = setting("LINK_HISTORY", "history", "on", conf).lower() not in OFF_VALUES
    ranker = vimium.Ranker(terms, time.time() * 1000)
    seen = set()
    hits = []

    # Rows enter the dedupe only once they are kept, unlike the default list.
    # There a snippet is always shown, so shadowing its history twin is right;
    # here a snippet the query missed would otherwise hide a row that matched.
    def keep(group, tag, title, url, command, when, row_tags):
        if tags and not row_tags & tags:
            return
        # Ranked against the shortened url the way the vomnibar does. The
        # scheme is on every row, so it can only dilute the score.
        text = vimium.shorten_url(url)
        if not ranker.matches(text, title):
            return
        key = pin_key(url, command)
        title_key = (urlsplit(url).netloc.lower(), title.casefold()) if url else None
        if key in seen or (title_key and title_key in seen):
            return
        seen.add(key)
        if title_key:
            seen.add(title_key)
        if when:
            score = ranker.relevancy(text, title, when * 1000)
        else:
            score = ranker.word_relevancy(text, title)
        hits.append((group, -score, len(hits), tag, title, url, command))

    # Group 0 is the pins, so a pin that matches at all stays above the ranking
    # rather than competing with it. Everything else is ranked against
    # everything else, bookmarks on word relevancy and history with its visit
    # time folded in, which is the split the extension makes.
    for url, title, command in load_pins(pins_path(conf)):
        keep(0, "#pin", title, url, command, 0, {"pin"})
    for title, command, url in load_snippets():
        keep(1, "#link", title, url, command, 0, {"link"})
    # A tag filter naming neither the bookmarks nor a profile leaves nothing in
    # the corpus worth reading, and reading it is the expensive part.
    corpus_tags = {"mark"} | {tag for tag, _ in history_dbs(profiles)}
    corpus = load_corpus(conf, profiles) if not tags or tags & corpus_tags else []
    for kind, tag, when, url, title in corpus:
        # Everything below this gate runs on a handful of rows. Splitting urls
        # and cleaning titles across all seventy thousand costs several times
        # what the ranking itself does, so nothing touches a row until its
        # terms are known to be in it.
        if not ranker.matches_in(url + "\n" + title):
            continue
        command = "xdg-open " + shlex.quote(url)
        if kind == "b":
            keep(1, "#mark", clean_title(title), url, command, 0, {"mark", tag})
            continue
        if not history_on or urlsplit(url).netloc.lower() in NOISE_HOSTS:
            continue
        title = clean_title(title)
        if not title or title == url:
            continue
        keep(1, "#" + tag, title, url, command, when, {tag})

    hits.sort()
    return [
        render(title, url, tag, command, pinned=group == 0)
        for group, _, _, tag, title, url, command in hits[:limit]
    ]


def main():
    conf, profiles = load_conf()

    if len(sys.argv) > 2 and sys.argv[1] == "--toggle-pin":
        toggle_pin(pins_path(conf), sys.argv[2])
        return

    if len(sys.argv) > 1 and sys.argv[1] == "--query":
        lines = run_search(conf, profiles, sys.argv[2] if len(sys.argv) > 2 else "")
    else:
        lines = default_lines(conf, profiles)

    if lines:
        sys.stdout.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    # stdout is always a pipe here: fzf on the hot path, head while debugging.
    # The default SIGPIPE disposition ends the process quietly when the reader
    # goes away, where python's would raise a traceback into the popup.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    main()
