import os
import re
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[2] / "scripts" / "__link_candidates.py"

SNIPPETS = """
[[Snippets]]
  Description = "Link to Zeta docs"
  Output = ""
  Tag = ["link"]
  command = "xdg-open https://zeta.example.com/docs"

[[Snippets]]
  Description = "Link to Zeta under its other name"
  Output = ""
  Tag = ["link"]
  command = "xdg-open https://zeta.example.com/docs"

[[Snippets]]
  Description = "Link to Alpha anchor"
  Output = ""
  Tag = ["link"]
  command = "xdg-open https://alpha.example.com/page/\\\\#:\\\\~:text\\\\=hit"
"""

# Chrome stores microseconds since 1601-01-01, Firefox since the unix epoch.
CHROME_EPOCH_OFFSET = 11644473600

ANSI = re.compile(r"\x1b\[[0-9;]*m")


# The display column: a pin marker, the title padded to its column, the url
# padded to its column, the tag. Colour codes wrap the url and the tag, so
# every reading of the column strips them first.
def plain(row):
    return ANSI.sub("", row[0])


def title_of(row):
    return plain(row)[2:].split("  ", 1)[0].strip()


def tag_of(row):
    return plain(row).rsplit("  ", 1)[-1].strip()


def titles(rows):
    return [title_of(row) for row in rows]


def firefox_db(path, rows):
    Path(path).unlink(missing_ok=True)
    conn = sqlite3.connect(path)
    conn.execute(
        "create table moz_places "
        "(id integer primary key, url text, title text, last_visit_date integer)"
    )
    conn.executemany(
        "insert into moz_places (url, title, last_visit_date) values (?, ?, ?)",
        [(url, title, int(when * 1000000)) for url, title, when in rows],
    )
    conn.commit()
    conn.close()


# Firefox keeps bookmarks in a table of their own, each pointing at a
# moz_places row. A bookmark never visited still has one, with no visit date,
# so it belongs to the bookmarks and not to history.
def bookmark_table(path, rows):
    conn = sqlite3.connect(path)
    conn.execute(
        "create table if not exists moz_bookmarks (fk integer, type integer, title text)"
    )
    for url, title in rows:
        found = conn.execute("select id from moz_places where url = ?", (url,)).fetchone()
        if found is None:
            cursor = conn.execute("insert into moz_places (url, title) values (?, '')", (url,))
            found = (cursor.lastrowid,)
        conn.execute("insert into moz_bookmarks values (?, 1, ?)", (found[0], title))
    conn.commit()
    conn.close()


def chrome_db(path, rows):
    Path(path).unlink(missing_ok=True)
    conn = sqlite3.connect(path)
    conn.execute("create table urls (url text, title text, last_visit_time integer)")
    conn.executemany(
        "insert into urls values (?, ?, ?)",
        [
            (url, title, int((when + CHROME_EPOCH_OFFSET) * 1000000))
            for url, title, when in rows
        ],
    )
    conn.commit()
    conn.close()


def pins_file(workdir):
    return Path(workdir) / "pins"


def run_script(workdir, dbs=(), conf_text=None, args=(), **env_overrides):
    snippet_file = Path(workdir) / "pet-links.toml"
    snippet_file.write_text(SNIPPETS)
    conf_file = Path(workdir) / "picker.conf"
    if conf_text is None:
        conf_file.unlink(missing_ok=True)
    else:
        conf_file.write_text(conf_text)

    # Never inherit the real machine's settings into a test run.
    env = {k: v for k, v in os.environ.items() if not k.startswith("LINK_")}
    env["PET_SNIPPET_FILE"] = str(snippet_file)
    env["LINK_PICKER_CONF"] = str(conf_file)
    # Without these two the defaults reach the real ~/.local/state files, and
    # the stream would carry this machine's own browser history.
    env["LINK_PINS_FILE"] = str(pins_file(workdir))
    env["LINK_CORPUS_FILE"] = str(Path(workdir) / "corpus")
    # The tail is built once per run rather than reused between them.
    env["LINK_CORPUS_TTL"] = "0"
    if dbs:
        env["LINK_HISTORY_DBS"] = ":".join(str(db) for db in dbs)
    elif conf_text is None:
        # Neither a db nor a conf naming profiles: pin history to a path that
        # matches nothing, or the default globs reach the real browser
        # profiles on whatever machine this runs on.
        env["LINK_HISTORY_DBS"] = str(Path(workdir) / "no-such-history.sqlite")
    env.update(env_overrides)

    result = subprocess.run(
        ["python3", str(SCRIPT), *args],
        text=True,
        capture_output=True,
        env=env,
        check=True,
    )
    return [tuple(line.split("\t")) for line in result.stdout.splitlines()]


class LinkCandidatesTest(unittest.TestCase):
    def setUp(self):
        self.workdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.workdir.cleanup)
        self.path = Path(self.workdir.name)

    def make_db(self, name, rows, kind="firefox"):
        db = self.path / name
        (firefox_db if kind == "firefox" else chrome_db)(db, rows)
        return db

    def candidates(self, firefox_rows=(), chrome_rows=(), **env):
        dbs = []
        if firefox_rows:
            dbs.append(self.make_db("places.sqlite", firefox_rows))
        if chrome_rows:
            dbs.append(self.make_db("History", chrome_rows, kind="chrome"))
        return run_script(self.workdir.name, dbs, **env)

    def history(self, rows):
        return [row for row in rows if tag_of(row) != "#link"]

    def test_history_leads_and_snippets_follow_sorted_and_tagged(self):
        rows = self.candidates(firefox_rows=[("https://a.example.com/", "A", 100)])
        self.assertEqual(title_of(rows[0]), "A")
        self.assertEqual(tag_of(rows[0]), "#history")
        self.assertEqual(title_of(rows[1]), "Alpha anchor")
        self.assertEqual(tag_of(rows[1]), "#link")
        self.assertEqual(title_of(rows[2]), "Zeta docs")

    def test_snippets_still_win_the_dedupe_from_below(self):
        # Order is display only: a bookmarked url must not come back a second
        # time as a history row just because history is emitted first.
        rows = self.candidates(
            firefox_rows=[
                ("https://zeta.example.com/docs", "Zeta docs the browser saw", 100),
                ("https://fresh.example.com/", "fresh", 90),
            ]
        )
        self.assertEqual(len(self.history(rows)), 1)
        self.assertEqual(title_of(rows[0]), "fresh")
        self.assertEqual(title_of(rows[2]), "Zeta docs")

    def test_snippet_command_survives_shell_escapes(self):
        # No history source, so the snippets are the whole list.
        rows = self.candidates()
        self.assertEqual(
            rows[0][1],
            r"xdg-open https://alpha.example.com/page/\#:\~:text\=hit",
        )
        # The display drops the escapes and the scheme, the command keeps them.
        self.assertIn("alpha.example.com/page/#:~:text=hit", plain(rows[0]))
        self.assertEqual(rows[0][3], "https://alpha.example.com/page/#:~:text=hit")

    def test_two_bookmarks_on_one_url_both_stay_searchable(self):
        # Two descriptions for one page are two ways to recall it. Only a pin
        # collapses them, never the presence of the other bookmark.
        rows = self.candidates()
        zeta = [row for row in rows if row[3] == "https://zeta.example.com/docs"]
        self.assertEqual(len(zeta), 2)

    def test_history_row_matching_a_snippet_is_dropped(self):
        rows = self.candidates(
            firefox_rows=[("https://zeta.example.com/docs", "Zeta docs", 100)]
        )
        self.assertEqual(self.history(rows), [])

    def test_notion_page_dedupes_across_hosts_and_query_strings(self):
        page = "a" * 32
        rows = self.candidates(
            firefox_rows=[
                ("https://www.notion.so/loftsh/Runbook-%s" % page, "Runbook | Notion", 100),
                ("https://app.notion.com/p/loftsh/%s?pvs=55" % page, "(7) Runbook | Notion", 200),
            ]
        )
        notion = [row for row in rows if "notion" in row[3]]
        self.assertEqual(len(notion), 1)
        # Newest visit wins, and the unread badge and app suffix are stripped.
        self.assertEqual(title_of(notion[0]), "Runbook")
        self.assertIn("app.notion.com", notion[0][1])

    def test_search_engine_rows_are_dropped(self):
        rows = self.candidates(
            firefox_rows=[
                ("https://duckduckgo.com/?q=netflix", "netflix at DuckDuckGo", 100),
                ("https://keep.example.com/x", "Keep me", 90),
            ]
        )
        self.assertEqual(titles(self.history(rows)), ["Keep me"])

    def test_same_title_on_one_host_collapses(self):
        rows = self.candidates(
            firefox_rows=[
                ("https://github.com/org/repo/pull/1", "fix: the thing", 100),
                ("https://github.com/org/repo/pull/1/changes", "fix: the thing", 90),
            ]
        )
        self.assertEqual(len(self.history(rows)), 1)

    # A repo root and its /tree/main view share a title. The root is the
    # address worth keeping, whichever of the two was opened last.
    def test_the_shortest_url_wins_a_title_collision(self):
        rows = self.candidates(
            firefox_rows=[
                ("https://github.com/me/classif/tree/main", "me/classif: a shell if", 300),
                ("https://other.example.com/", "other", 200),
                ("https://github.com/me/classif", "me/classif: a shell if", 100),
            ]
        )
        history = self.history(rows)
        self.assertEqual(titles(history), ["me/classif: a shell if", "other"])
        self.assertEqual(history[0][3], "https://github.com/me/classif")

    def test_per_host_cap_keeps_a_busy_host_from_taking_over(self):
        rows = self.candidates(
            firefox_rows=[
                ("https://github.com/org/repo/pull/1", "first pr", 100),
                ("https://github.com/org/repo/pull/2", "second pr", 90),
                ("https://other.example.com/x", "other page", 80),
            ],
            LINK_HISTORY_PER_HOST="1",
        )
        # The capped row is not lost: it comes back in the tail.
        self.assertEqual(titles(self.history(rows)), ["first pr", "other page", "second pr"])

    def test_history_limit_and_kill_switch(self):
        firefox_rows = [
            ("https://one.example.com/", "one", 100),
            ("https://two.example.com/", "two", 90),
        ]
        capped = self.candidates(firefox_rows=firefox_rows, LINK_HISTORY_LIMIT="1")
        self.assertEqual(titles(self.history(capped)), ["one", "two"])
        self.assertEqual(tag_of(capped[0]), "#history")

        off = self.candidates(firefox_rows=firefox_rows, LINK_HISTORY="0")
        self.assertEqual(self.history(off), [])

    def test_history_command_is_quoted_for_eval(self):
        rows = self.candidates(
            chrome_rows=[("https://ci.example.com/job?id=7&x=1", "Job 7", 100)]
        )
        self.assertEqual(
            self.history(rows)[0][1], "xdg-open 'https://ci.example.com/job?id=7&x=1'"
        )

    def test_untitled_rows_are_skipped(self):
        rows = self.candidates(
            firefox_rows=[
                ("https://blank.example.com/", "", 100),
                ("https://good.example.com/", "Good", 90),
            ]
        )
        self.assertEqual(titles(self.history(rows)), ["Good"])

    # fzf reads the colour out of the display column (--ansi) and nothing
    # else may carry it: field 2 is eval'd, 3 and 4 are written to the pins.
    def test_colour_lives_in_the_display_column_only(self):
        rows = self.candidates(firefox_rows=[("https://a.example.com/", "A", 100)])
        for row in rows:
            self.assertIn("\x1b[", row[0])
            for field in row[1:]:
                self.assertNotIn("\x1b", field)

    def test_the_hidden_key_column_is_the_dedupe_key(self):
        rows = self.candidates(
            firefox_rows=[("https://A.example.com/path/?x=1", "A", 100)]
        )
        self.assertEqual(rows[0][4], "a.example.com/path?x=1")


class ConfFileTest(unittest.TestCase):
    """The picker runs from a hotkey with no shell environment, so the conf
    file is the only setting channel that reaches it."""

    def setUp(self):
        self.workdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.workdir.cleanup)
        self.path = Path(self.workdir.name)
        self.work_db = self.path / "work.sqlite"
        self.home_db = self.path / "home.sqlite"
        firefox_db(
            self.work_db,
            [
                ("https://linear.app/issue/1", "work issue", 300),
                ("https://github.com/org/a", "work repo a", 200),
                ("https://github.com/org/b", "work repo b", 190),
            ],
        )
        firefox_db(
            self.home_db,
            [
                ("https://github.com/me/dotfiles", "home repo", 100),
                ("https://youtube.com/watch?v=1", "home video", 90),
            ],
        )

    def conf(self, *extra):
        lines = list(extra) + [
            "profile = work:%s" % self.work_db,
            "profile = home:%s" % self.home_db,
        ]
        return "\n".join(lines) + "\n"

    def candidates(self, *extra, **env):
        return run_script(self.workdir.name, conf_text=self.conf(*extra), **env)

    # The recent block: everything above the snippets. The tail below them
    # is covered by StreamTest.
    def recent(self, rows):
        for index, row in enumerate(rows):
            if tag_of(row) == "#link":
                return rows[:index]
        return rows

    def test_profile_tag_rides_on_its_rows(self):
        rows = self.recent(self.candidates())
        tags = [tag_of(row) for row in rows]
        self.assertEqual(tags.count("#work"), 3)
        self.assertEqual(tags.count("#home"), 2)
        self.assertEqual(title_of(rows[0]), "work issue")

    def test_profiles_group_in_conf_order_with_recency_inside(self):
        # Interleaved in time, so a plain newest-first sort would drop the
        # home rows in between the work ones.
        firefox_db(
            self.work_db,
            [
                ("https://linear.app/issue/1", "work newest", 300),
                ("https://linear.app/issue/2", "work oldest", 100),
            ],
        )
        firefox_db(
            self.home_db,
            [
                ("https://youtube.com/watch?v=1", "home newest", 250),
                ("https://youtube.com/watch?v=2", "home oldest", 150),
            ],
        )
        rows = self.recent(self.candidates())
        self.assertEqual(
            titles(rows), ["work newest", "work oldest", "home newest", "home oldest"]
        )

    def test_swapping_the_conf_blocks_flips_the_groups(self):
        # Nothing hardcodes "work": the conf order is what decides.
        conf_text = "profile = home:%s\nprofile = work:%s\n" % (
            self.home_db,
            self.work_db,
        )
        rows = self.recent(run_script(self.workdir.name, conf_text=conf_text))
        self.assertEqual([tag_of(row) for row in rows], ["#home"] * 2 + ["#work"] * 3)

    def test_conf_limit_is_applied(self):
        self.assertEqual(len(self.recent(self.candidates("limit = 2"))), 2)

    def test_env_beats_conf(self):
        rows = self.recent(self.candidates("limit = 2", LINK_HISTORY_LIMIT="4"))
        self.assertEqual(len(rows), 4)

    def test_conf_can_switch_history_off(self):
        rows = self.candidates("history = off")
        self.assertEqual({tag_of(row) for row in rows}, {"#link"})

    def test_per_host_cap_counts_within_a_profile(self):
        # github.com appears in both profiles: a cap of 1 keeps one row from
        # each, rather than letting work github consume the only slot.
        rows = self.recent(self.candidates("per_host = 1"))
        github = [row for row in rows if "github.com" in row[1]]
        self.assertEqual(sorted(tag_of(row) for row in github), ["#home", "#work"])

    def test_comments_and_blank_lines_are_ignored(self):
        rows = self.recent(self.candidates("# limit = 1", "", "   ", "limit = 2"))
        self.assertEqual(len(rows), 2)


class PinTest(unittest.TestCase):
    """ctrl-f writes a whole row to the pins file; pinned rows float above
    both history and the bookmarks."""

    def setUp(self):
        self.workdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.workdir.cleanup)
        self.path = Path(self.workdir.name)
        self.db = self.path / "places.sqlite"
        firefox_db(
            self.db,
            [
                ("https://recent.example.com/", "recent page", 300),
                ("https://older.example.com/", "older page", 200),
            ],
        )

    def write_pins(self, *rows):
        pins_file(self.workdir.name).write_text(
            "".join("\t".join(row) + "\n" for row in rows)
        )

    def candidates(self, **env):
        return run_script(self.workdir.name, dbs=[self.db], **env)

    def test_a_pin_sits_above_history_and_bookmarks(self):
        self.write_pins(
            ("https://older.example.com/", "older page", "xdg-open 'https://older.example.com/'")
        )
        rows = self.candidates()
        self.assertEqual(tag_of(rows[0]), "#pin")
        self.assertTrue(plain(rows[0]).startswith("* "), plain(rows[0]))
        self.assertEqual(title_of(rows[0]), "older page")
        # And it is not also still down in the history block or the tail.
        self.assertEqual(len([r for r in rows if "older.example.com" in r[3]]), 1)

    def test_pinning_a_bookmark_takes_it_out_of_the_link_block(self):
        self.write_pins(
            ("https://zeta.example.com/docs", "Zeta docs", "xdg-open https://zeta.example.com/docs")
        )
        rows = self.candidates()
        zeta = [row for row in rows if title_of(row) == "Zeta docs"]
        self.assertEqual(len(zeta), 1)
        self.assertEqual(tag_of(zeta[0]), "#pin")

    def test_a_pin_outlives_the_row_it_was_made_from(self):
        # Nothing in history or the snippets points here any more.
        self.write_pins(
            ("https://gone.example.com/doc", "long gone", "xdg-open 'https://gone.example.com/doc'")
        )
        rows = self.candidates()
        self.assertEqual(title_of(rows[0]), "long gone")
        self.assertEqual(rows[0][1], "xdg-open 'https://gone.example.com/doc'")

    def test_toggle_pins_then_unpins_the_same_row(self):
        row = self.candidates()[0]
        self.assertEqual(tag_of(row), "#history")

        run_script(self.workdir.name, dbs=[self.db], args=["--toggle-pin", "\t".join(row)])
        after = self.candidates()
        self.assertEqual(tag_of(after[0]), "#pin")
        self.assertEqual(title_of(after[0]), "recent page")

        run_script(
            self.workdir.name, dbs=[self.db], args=["--toggle-pin", "\t".join(after[0])]
        )
        self.assertEqual(tag_of(self.candidates()[0]), "#history")

    def test_hidden_columns_carry_the_untruncated_title_and_url(self):
        long_title = "a very long tab title that the display column has to cut short " * 2
        long_url = "https://long.example.com/" + "segment/" * 20
        firefox_db(self.db, [(long_url, long_title, 300)])
        row = self.candidates()[0]
        # Display is truncated, the hidden columns are not, so a pin made from
        # this row stores the real title and url rather than "...".
        self.assertIn("...", plain(row))
        self.assertEqual(row[2], " ".join(long_title.split()))
        self.assertEqual(row[3], long_url)


class StreamTest(unittest.TestCase):
    """Below the recent rows and the snippets comes the long tail: every
    bookmark and history row the profiles hold, rendered once into a cache
    and streamed from it, so fzf searches all of it. fzf does the matching;
    these cover what is in the stream and in what order."""

    def setUp(self):
        self.workdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.workdir.cleanup)
        self.path = Path(self.workdir.name)
        self.db = self.path / "places.sqlite"
        self.corpus = self.path / "corpus"

    def stream(self, **env):
        return run_script(self.workdir.name, [self.db], **env)

    # Everything after the snippets, which close the recent block.
    def tail(self, rows):
        last = max((i for i, row in enumerate(rows) if tag_of(row) == "#link"), default=-1)
        return rows[last + 1 :]

    def test_a_row_past_the_history_limit_is_still_streamed(self):
        # The recent block holds one row; the stream still reaches the other
        # twenty, which is the reach the picker was missing.
        firefox_db(self.db, [
            ("https://e.example.com/%d" % n, "page %d" % n, 100 + n) for n in range(20)
        ] + [("https://needle.example.com/", "the needle", 1)])
        rows = self.stream(LINK_HISTORY_LIMIT="1")
        self.assertEqual(titles(rows)[0], "page 19")
        self.assertEqual(titles(rows).count("the needle"), 1)
        self.assertEqual(titles(self.tail(rows))[-1], "the needle")

    def test_the_tail_is_bookmarks_first_then_history_newest_first(self):
        firefox_db(self.db, [
            ("https://old.example.com/", "old page", 100),
            ("https://older.example.com/", "older page", 50),
            ("https://new.example.com/", "new page", 300),
        ])
        bookmark_table(self.db, [("https://saved.example.com/doc", "the saved doc")])
        rows = self.stream(LINK_HISTORY_LIMIT="1")
        self.assertEqual(titles(self.tail(rows)), ["the saved doc", "old page", "older page"])
        self.assertEqual(tag_of(self.tail(rows)[0]), "#mark")
        self.assertEqual(tag_of(self.tail(rows)[1]), "#history")

    def test_bookmarks_can_be_turned_off(self):
        firefox_db(self.db, [("https://a.example.com/", "unrelated", 300)])
        bookmark_table(self.db, [("https://saved.example.com/doc", "the saved doc")])
        self.assertNotIn("the saved doc", titles(self.stream(LINK_BOOKMARKS="0")))

    # A places file with no bookmark tables must not take its history with it.
    def test_a_profile_without_bookmark_tables_still_fills_the_tail(self):
        firefox_db(self.db, [
            ("https://a.example.com/", "findable", 300),
            ("https://b.example.com/", "also findable", 200),
        ])
        rows = self.stream(LINK_HISTORY_LIMIT="1")
        self.assertEqual(titles(self.tail(rows)), ["also findable"])

    def test_the_tail_repeats_nothing_the_recent_block_holds(self):
        # The same page under a query string, and the same title under a
        # second path, both collapse onto the recent row.
        firefox_db(self.db, [
            ("https://a.example.com/doc", "the doc", 300),
            ("https://a.example.com/doc?utm=1", "the doc", 200),
            ("https://a.example.com/doc/changes", "the doc", 100),
            ("https://zeta.example.com/docs", "Zeta docs as the browser saw it", 90),
        ])
        rows = self.stream()
        self.assertEqual(titles(rows).count("the doc"), 1)
        self.assertEqual(len([r for r in rows if "zeta.example.com" in r[3]]), 2)
        self.assertEqual(self.tail(rows), [])

    def test_the_tail_keeps_the_shortest_url_for_a_title(self):
        firefox_db(self.db, [
            ("https://a.example.com/", "recent", 300),
            ("https://github.com/me/classif/tree/main", "me/classif: a shell if", 200),
            ("https://github.com/me/classif", "me/classif: a shell if", 100),
        ])
        tail = self.tail(self.stream(LINK_HISTORY_LIMIT="1"))
        self.assertEqual(titles(tail), ["me/classif: a shell if"])
        self.assertEqual(tail[0][3], "https://github.com/me/classif")
        self.assertEqual(tail[0][1], "xdg-open https://github.com/me/classif")

    def test_a_shorter_tail_url_replaces_the_recent_rows_address(self):
        # The branch view is today's page, the root sits in the tail: the
        # recent row keeps its place and takes the root address.
        firefox_db(self.db, [
            ("https://github.com/me/classif/tree/main", "me/classif: a shell if", 300),
            ("https://github.com/me/classif", "me/classif: a shell if", 100),
        ])
        rows = self.stream(LINK_HISTORY_LIMIT="1")
        self.assertEqual(titles(rows).count("me/classif: a shell if"), 1)
        self.assertEqual(rows[0][3], "https://github.com/me/classif")
        self.assertEqual(rows[0][1], "xdg-open https://github.com/me/classif")
        self.assertEqual(tag_of(rows[0]), "#history")

    def test_a_cache_in_an_older_format_is_rebuilt(self):
        firefox_db(self.db, [
            ("https://a.example.com/", "recent", 300),
            ("https://b.example.com/", "tail row", 200),
        ])
        self.corpus.write_text("h\thistory\t200\thttps://b.example.com/\told format\n")
        self.assertEqual(titles(self.tail(self.stream(LINK_HISTORY_LIMIT="1"))), ["tail row"])

    def test_search_engine_rows_stay_out_of_the_tail(self):
        firefox_db(self.db, [
            ("https://keep.example.com/", "keep", 300),
            ("https://duckduckgo.com/?q=netflix", "netflix at DuckDuckGo", 200),
            ("https://also.example.com/", "also", 100),
        ])
        rows = self.stream(LINK_HISTORY_LIMIT="1")
        self.assertEqual(titles(self.tail(rows)), ["also"])

    def test_the_tail_is_cached_and_streamed_from_the_cache(self):
        firefox_db(self.db, [
            ("https://a.example.com/", "recent", 300),
            ("https://b.example.com/", "tail row", 200),
        ])
        self.stream(LINK_HISTORY_LIMIT="1")
        self.assertTrue(self.corpus.exists())
        # Rewritten by hand: the next stream must answer out of it rather than
        # go back to the database.
        self.corpus.write_text(
            "#link-picker-corpus 2\n" + "\t".join([
                "  cached row",
                "xdg-open 'https://cached.example.com/'",
                "cached row",
                "https://cached.example.com/",
                "cached.example.com",
            ]) + "\n"
        )
        self.assertEqual(titles(self.tail(self.stream(LINK_HISTORY_LIMIT="1"))), ["cached row"])

    def test_refresh_rebuilds_the_cache_once_a_database_moved_on(self):
        firefox_db(self.db, [
            ("https://a.example.com/", "recent", 300),
            ("https://b.example.com/", "first tail", 200),
        ])
        self.stream(LINK_HISTORY_LIMIT="1")
        firefox_db(self.db, [
            ("https://a.example.com/", "recent", 300),
            ("https://c.example.com/", "second tail", 200),
        ])
        run_script(self.workdir.name, [self.db], args=["--refresh"])
        self.assertEqual(titles(self.tail(self.stream(LINK_HISTORY_LIMIT="1"))), ["second tail"])

    # The rebuild used to run inline on the keystroke that found the cache
    # stale, and fzf killed it on the next key. The popup now takes the cache
    # as it is; the runner refreshes it in the background as the popup opens.
    def test_the_popup_never_rebuilds_the_cache_itself(self):
        firefox_db(self.db, [
            ("https://a.example.com/", "recent", 300),
            ("https://b.example.com/", "first tail", 200),
        ])
        self.stream(LINK_HISTORY_LIMIT="1")
        firefox_db(self.db, [
            ("https://a.example.com/", "recent", 300),
            ("https://c.example.com/", "second tail", 200),
        ])
        self.assertEqual(titles(self.tail(self.stream(LINK_HISTORY_LIMIT="1"))), ["first tail"])

    def test_refresh_within_the_ttl_leaves_the_cache_alone(self):
        firefox_db(self.db, [
            ("https://a.example.com/", "recent", 300),
            ("https://b.example.com/", "first tail", 200),
        ])
        self.stream(LINK_HISTORY_LIMIT="1")
        firefox_db(self.db, [
            ("https://a.example.com/", "recent", 300),
            ("https://c.example.com/", "second tail", 200),
        ])
        run_script(self.workdir.name, [self.db], args=["--refresh"], LINK_CORPUS_TTL="3600")
        self.assertEqual(titles(self.tail(self.stream(LINK_HISTORY_LIMIT="1"))), ["first tail"])


if __name__ == "__main__":
    unittest.main()
