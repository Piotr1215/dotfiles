#!/usr/bin/env python3
"""Emit link picker rows as "display<TAB>command<TAB>title<TAB>url<TAB>key".

Three sources feed the picker: the curated pet link snippets, the browser's
own bookmarks, and browser history from the LibreWolf and Chrome profiles
named in the conf. Pinned rows come first, then recent history grouped by
profile in conf order and newest first inside each group, then the snippets
alphabetically, then the long tail: every bookmark and every history row the
profiles hold, newest first. The tail is what a search reaches that the recent
list does not; Vimium C's omnibox found pages this picker could not until it
was there.

__link_pane_runner.sh pipes this into fzf once. fzf matches, ranks and
highlights; this script decides only what is in the list and in what order.
fzf's history scheme keeps that order among equal matches, so a page seen
today sits above the same word on a page from last year. The ranking that
used to live here (a port of Vimium C's) needed a subprocess per keystroke and
matched a typed word only unbroken, so "classifreadme" found nothing; fzf
finds classif/README.md and puts it first.

The display column carries colour, which fzf --ansi reads: the title plain,
the url dimmed, the source tag in its own colour. The hidden columns carry
the command to run on selection, the untruncated title and url that ctrl-f
writes to the pins file and fzf also matches against (--nth=1,3,4), and the
dedupe key. The runner cuts field 2 only, so eval never sees the rest.

The long tail is cached rendered, because building it means copying a hundred
megabytes of locked sqlite and formatting seventy thousand rows. --refresh
rebuilds it when a source database has moved on and the cache is older than
the ttl; the runner starts that in the background as the popup opens, so the
popup never waits on it. Pins, snippets and the recent rows are always read
live, so a ctrl-f pin shows up on the next reload.

Settings live in __link_picker.conf, because the picker runs from a global
hotkey and that process carries none of the shell environment. The variables
below still win when they are set, for one-off runs from a terminal.

Environment:
  PET_SNIPPET_FILE       pet links toml (default ~/dev/pet-snippets/pet-links.toml)
  LINK_PICKER_CONF       settings file (default ~/dev/dotfiles/scripts/__link_picker.conf)
  LINK_HISTORY           set to 0 to drop the history rows entirely
  LINK_HISTORY_LIMIT     how many recent history rows to keep (default 500)
  LINK_HISTORY_PER_HOST  cap per host per profile, keeps github off the whole list
  LINK_HISTORY_DBS       colon separated paths or globs, replaces the conf profiles
  LINK_PINS_FILE         pinned rows (default ~/.local/state/link-picker/pins)
  LINK_CORPUS_FILE       rendered long tail (default ~/.local/state/link-picker/corpus)
  LINK_CORPUS_TTL        seconds before the cache may be rebuilt (default 300)
  LINK_BOOKMARKS         set to 0 to leave browser bookmarks out of the tail

Subcommands:
  --toggle-pin <line>    pin or unpin the row, called from the ctrl-f binding
  --refresh              rebuild the long tail if it has fallen behind
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

# The long tail is derived state, so it sits next to the pins rather than in
# the repo, for the same reason.
DEFAULT_CORPUS_FILE = "~/.local/state/link-picker/corpus"

# A running browser touches its history write ahead log constantly, so mtime
# alone would rebuild the tail on every launch. This is the floor between
# rebuilds; within it the picker streams whatever it already has.
DEFAULT_CORPUS_TTL = "300"

# First line of the cache. A cache written by an earlier format would stream
# as garbage rows, so one that does not open with this is rebuilt.
CORPUS_FORMAT = "#link-picker-corpus 2"

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

# The same rows without the recency window, for the long tail. A page from
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

TITLE_WIDTH = 70
URL_WIDTH = 80

# Dracula, the same palette the runner hands fzf. The url is dimmed to the
# comment colour so the eye lands on the title; the tag names its source.
RESET = "\x1b[0m"
DIM = "\x1b[38;2;98;114;164m"
TAG_COLOURS = {
    "#pin": "\x1b[38;2;255;121;198m",
    "#link": "\x1b[38;2;80;250;123m",
    "#mark": "\x1b[38;2;189;147;249m",
    "#work": "\x1b[38;2;255;184;108m",
    "#home": "\x1b[38;2;139;233;253m",
}
PIN_MARK = TAG_COLOURS["#pin"] + "*" + RESET

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
SCHEME = re.compile(r"^https?://", re.IGNORECASE)


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


# Same page under a different path (a PR and its /changes tab, a repo and its
# /tree/main view) shares a title, so this collapses what the url key cannot.
# Where titles collide the shortest url is kept, because that is the
# canonical address: the repo root, not the branch view it redirected to.
def title_key(url, title):
    return (urlsplit(url).netloc.lower(), title.casefold())


# Snippet commands carry shell escapes (\# and \~ in anchors); undo them for
# display only. The command itself is passed through untouched.
def url_from_command(command):
    found = XDG_OPEN_URL.match(command)
    return found.group(1).replace("\\", "") if found else ""


def clip(text, width):
    return text if len(text) <= width else text[: width - 3] + "..."


# The scheme is on every row, so showing it only costs the eight columns the
# interesting end of the url needed.
def display_url(url):
    return SCHEME.sub("", url).rstrip("/")


def render(title, url, tag, command, pinned=False):
    title = " ".join(title.split())
    colour = TAG_COLOURS.get(tag, DIM)
    display = "%s %-*s  %s%-*s%s  %s%s%s" % (
        PIN_MARK if pinned else " ",
        TITLE_WIDTH,
        clip(title, TITLE_WIDTH),
        DIM,
        URL_WIDTH,
        clip(display_url(url), URL_WIDTH),
        RESET,
        colour,
        tag,
        RESET,
    )
    return "\t".join([display, command, title, url, pin_key(url, command)])


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


def switched_on(env_name, conf_key, conf):
    return setting(env_name, conf_key, "on", conf).lower() not in OFF_VALUES


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
    shortest = {}
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
        by_title = (host, title.casefold())
        if by_title in seen:
            index = shortest.get(by_title)
            if index is not None and len(url) < len(hits[index][1]):
                hits[index] = (title, url, hits[index][2])
                seen.add(key)
            continue
        seen.add(key)
        seen.add(by_title)
        shortest[by_title] = len(hits)
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
# megabytes of sqlite copying on every launch.
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


# The long tail, rendered and in its final order: bookmarks first, since each
# was saved on purpose, then history newest first. Deduped the way the recent
# list is, so a page reached under three query strings is one row.
def build_corpus(path, sources, bookmarks_on, history_on):
    rows = []
    with tempfile.TemporaryDirectory(prefix="link-corpus-") as workdir:
        for index, (tag, source) in enumerate(sources):
            try:
                history, marks = read_db_corpus(source, workdir, index, bookmarks_on)
            except (OSError, sqlite3.Error) as err:
                print("link candidates: %s: %s" % (source, err), file=sys.stderr)
                continue
            for url, title in marks:
                rows.append((0, 0, "#mark", url, title or ""))
            if history_on:
                for url, title, when in history:
                    rows.append((1, -(when or 0), "#" + tag, url, title or ""))
    rows.sort(key=lambda row: row[:2])

    seen = set()
    shortest = {}
    lines = []
    for group, _, tag, url, title in rows:
        url, title = flatten(url), flatten(title)
        host = urlsplit(url).netloc.lower()
        if group and host in NOISE_HOSTS:
            continue
        title = clean_title(title)
        if not title or title == url:
            continue
        key, by_title = dedupe_key(url), (host, title.casefold())
        if key in seen:
            continue
        if by_title in seen:
            index, kept_url, kept_tag = shortest[by_title]
            if len(url) < len(kept_url):
                shortest[by_title] = (index, url, kept_tag)
                lines[index] = render(title, url, kept_tag, "xdg-open " + shlex.quote(url))
            seen.add(key)
            continue
        seen.add(key)
        seen.add(by_title)
        shortest[by_title] = (len(lines), url, tag)
        lines.append(render(title, url, tag, "xdg-open " + shlex.quote(url)))

    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    # Written aside and renamed, so a picker reading the cache while another
    # rebuilds it never reads half a file.
    scratch = "%s.%d" % (path, os.getpid())
    try:
        with open(scratch, "w") as handle:
            handle.write(CORPUS_FORMAT + "\n")
            for line in lines:
                handle.write(line + "\n")
        os.replace(scratch, path)
    except OSError as err:
        print("link candidates: %s: %s" % (path, err), file=sys.stderr)
    return lines


# The --refresh subcommand. The runner starts this in the background as the
# popup opens. It once ran inline on the keystroke that found the cache stale,
# where fzf killed it as soon as the next key arrived, left the half written
# scratch file behind, and started it over on the key after that.
def refresh_corpus(conf, profiles):
    path = corpus_path(conf)
    sources = history_dbs(profiles)
    ttl = float(setting("LINK_CORPUS_TTL", "corpus_ttl", DEFAULT_CORPUS_TTL, conf))
    if corpus_stale(path, sources, ttl):
        build_corpus(
            path,
            sources,
            switched_on("LINK_BOOKMARKS", "bookmarks", conf),
            switched_on("LINK_HISTORY", "history", conf),
        )


# The popup takes the cache as it is. Only a missing, unreadable or outdated
# cache is built here, which is the first run on a machine and nothing after.
# Read as bytes and decoded by hand: the text layer's newline handling costs
# more than the read and the decode together on fourteen megabytes.
def load_corpus(conf, profiles):
    path = corpus_path(conf)
    try:
        with open(path, "rb") as handle:
            lines = handle.read().decode("utf-8", "replace").split("\n")
        if lines and lines[0] == CORPUS_FORMAT:
            return lines[1:]
    except OSError:
        pass
    return build_corpus(
        path,
        history_dbs(profiles),
        switched_on("LINK_BOOKMARKS", "bookmarks", conf),
        switched_on("LINK_HISTORY", "history", conf),
    )


def default_rows(conf, profiles):
    """The recent block as (title, url, tag, command, pinned) rows: pins,
    today's history grouped by profile, the snippets."""
    history_on = switched_on("LINK_HISTORY", "history", conf)
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
            seen.add(title_key(url, title))
        rows.append((title, url, "#pin", command, True))

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
        snippets.append((title, url, "#link", command, False))

    # History next, because the picker is reached for to get back to a page
    # from earlier today. The bookmarks are the long tail you search for by
    # name, so they sit underneath.
    if history_on:
        for title, url, tag in load_history(seen, profiles, limit, per_host_limit):
            rows.append((title, url, "#" + tag, "xdg-open " + shlex.quote(url), False))
    rows.extend(snippets)
    return rows


# The recent block goes out first and is flushed, so fzf is on screen with it
# while the tail streams in behind. A tail row is dropped when the recent
# block already holds its page, by key or by host and title, which is the
# dedupe the recent block applies to itself; a tail row with a shorter url
# for a history row's title hands that url over first, so the repo root wins
# over the branch view whichever was seen last. Pins and snippets keep the
# url they were written with.
def stream(conf, profiles, out):
    recent = default_rows(conf, profiles)
    tail = load_corpus(conf, profiles)

    seen = set()
    titles = {}
    for index, (title, url, tag, command, _) in enumerate(recent):
        seen.add(pin_key(url, command))
        if url:
            seen.add(title_key(url, title))
            titles.setdefault(title.casefold(), index)

    # The cache may predate a flip of the history switch, so the switch is
    # applied here too: with history off only the bookmarks stream.
    history_on = switched_on("LINK_HISTORY", "history", conf)

    # The title check splits the url, which across seventy thousand rows costs
    # more than the whole stream, so it runs only where the title collides.
    kept = []
    for line in tail:
        fields = line.split("\t")
        if len(fields) < 5 or fields[4] in seen:
            continue
        if not history_on and "#mark" not in fields[0]:
            continue
        index = titles.get(fields[2].casefold())
        if index is not None and title_key(fields[3], fields[2]) in seen:
            title, url, tag, command, pinned = recent[index]
            if tag not in ("#pin", "#link") and len(fields[3]) < len(url):
                recent[index] = (title, fields[3], tag, fields[1], pinned)
            continue
        kept.append(line)

    lines = [render(*row) for row in recent]
    if lines:
        out.write("\n".join(lines) + "\n")
        out.flush()
    if kept:
        out.write("\n".join(kept) + "\n")


def main():
    conf, profiles = load_conf()

    if len(sys.argv) > 2 and sys.argv[1] == "--toggle-pin":
        toggle_pin(pins_path(conf), sys.argv[2])
        return

    if len(sys.argv) > 1 and sys.argv[1] == "--refresh":
        refresh_corpus(conf, profiles)
        return

    stream(conf, profiles, sys.stdout)


if __name__ == "__main__":
    # stdout is always a pipe here: fzf on the hot path, head while debugging.
    # The default SIGPIPE disposition ends the process quietly when the reader
    # goes away, where python's would raise a traceback into the popup.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    main()
