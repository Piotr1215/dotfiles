import os
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
    # the search would answer out of this machine's own browser history.
    env["LINK_PINS_FILE"] = str(pins_file(workdir))
    env["LINK_CORPUS_FILE"] = str(Path(workdir) / "corpus")
    # The corpus is built once per run rather than reused between them.
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
        return [row for row in rows if "#link" not in row[0]]

    def test_history_leads_and_snippets_follow_sorted_and_tagged(self):
        rows = self.candidates(firefox_rows=[("https://a.example.com/", "A", 100)])
        self.assertIn("[A]", rows[0][0])
        self.assertIn("#history", rows[0][0])
        self.assertIn("[Alpha anchor]", rows[1][0])
        self.assertIn("#link", rows[1][0])
        self.assertIn("[Zeta docs]", rows[2][0])

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
        self.assertIn("[fresh]", rows[0][0])
        self.assertIn("[Zeta docs]", rows[2][0])

    def test_snippet_command_survives_shell_escapes(self):
        # No history source, so the snippets are the whole list.
        rows = self.candidates()
        self.assertEqual(
            rows[0][1],
            r"xdg-open https://alpha.example.com/page/\#:\~:text\=hit",
        )
        # The display drops the escapes, the command keeps them.
        self.assertIn("https://alpha.example.com/page/#:~:text=hit", rows[0][0])

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
        notion = [row for row in rows if "notion" in row[0]]
        self.assertEqual(len(notion), 1)
        # Newest visit wins, and the unread badge and app suffix are stripped.
        self.assertIn("[Runbook]", notion[0][0])
        self.assertIn("app.notion.com", notion[0][1])

    def test_search_engine_rows_are_dropped(self):
        rows = self.candidates(
            firefox_rows=[
                ("https://duckduckgo.com/?q=netflix", "netflix at DuckDuckGo", 100),
                ("https://keep.example.com/x", "Keep me", 90),
            ]
        )
        history = self.history(rows)
        self.assertEqual(len(history), 1)
        self.assertIn("[Keep me]", history[0][0])

    def test_same_title_on_one_host_collapses(self):
        rows = self.candidates(
            firefox_rows=[
                ("https://github.com/org/repo/pull/1", "fix: the thing", 100),
                ("https://github.com/org/repo/pull/1/changes", "fix: the thing", 90),
            ]
        )
        self.assertEqual(len(self.history(rows)), 1)

    def test_per_host_cap_keeps_a_busy_host_from_taking_over(self):
        rows = self.candidates(
            firefox_rows=[
                ("https://github.com/org/repo/pull/1", "first pr", 100),
                ("https://github.com/org/repo/pull/2", "second pr", 90),
                ("https://other.example.com/x", "other page", 80),
            ],
            LINK_HISTORY_PER_HOST="1",
        )
        history = self.history(rows)
        self.assertEqual(len(history), 2)
        self.assertIn("[first pr]", history[0][0])
        self.assertIn("[other page]", history[1][0])

    def test_history_limit_and_kill_switch(self):
        firefox_rows = [
            ("https://one.example.com/", "one", 100),
            ("https://two.example.com/", "two", 90),
        ]
        capped = self.candidates(firefox_rows=firefox_rows, LINK_HISTORY_LIMIT="1")
        self.assertEqual(len(self.history(capped)), 1)

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
        history = self.history(rows)
        self.assertEqual(len(history), 1)
        self.assertIn("[Good]", history[0][0])


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

    def history(self, rows):
        return [row for row in rows if "#link" not in row[0]]

    def test_profile_tag_rides_on_its_rows(self):
        rows = self.history(self.candidates())
        tags = [row[0].rsplit("  ", 1)[-1].strip() for row in rows]
        self.assertEqual(tags.count("#work"), 3)
        self.assertEqual(tags.count("#home"), 2)
        self.assertIn("[work issue]", rows[0][0])

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
        rows = self.history(self.candidates())
        titles = [row[0].split("]")[0].strip().lstrip("[") for row in rows]
        self.assertEqual(
            titles, ["work newest", "work oldest", "home newest", "home oldest"]
        )

    def test_swapping_the_conf_blocks_flips_the_groups(self):
        # Nothing hardcodes "work": the conf order is what decides.
        conf_text = "profile = home:%s\nprofile = work:%s\n" % (
            self.home_db,
            self.work_db,
        )
        rows = self.history(run_script(self.workdir.name, conf_text=conf_text))
        tags = [row[0].rsplit("  ", 1)[-1].strip() for row in rows]
        self.assertEqual(tags, ["#home"] * 2 + ["#work"] * 3)

    def test_conf_limit_is_applied(self):
        rows = self.history(self.candidates("limit = 2"))
        self.assertEqual(len(rows), 2)

    def test_env_beats_conf(self):
        rows = self.history(self.candidates("limit = 2", LINK_HISTORY_LIMIT="4"))
        self.assertEqual(len(rows), 4)

    def test_conf_can_switch_history_off(self):
        self.assertEqual(self.history(self.candidates("history = off")), [])

    def test_per_host_cap_counts_within_a_profile(self):
        # github.com appears in both profiles: a cap of 1 keeps one row from
        # each, rather than letting work github consume the only slot.
        rows = self.history(self.candidates("per_host = 1"))
        github = [row for row in rows if "github.com" in row[1]]
        self.assertEqual(len(github), 2)
        self.assertIn("#work", [row[0].rsplit("  ", 1)[-1].strip() for row in github])
        self.assertIn("#home", [row[0].rsplit("  ", 1)[-1].strip() for row in github])

    def test_comments_and_blank_lines_are_ignored(self):
        rows = self.history(self.candidates("# limit = 1", "", "   ", "limit = 2"))
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

    def tag_of(self, row):
        return row[0].rsplit("  ", 1)[-1].strip()

    def test_a_pin_sits_above_history_and_bookmarks(self):
        self.write_pins(
            ("https://older.example.com/", "older page", "xdg-open 'https://older.example.com/'")
        )
        rows = self.candidates()
        self.assertEqual(self.tag_of(rows[0]), "#pin")
        self.assertTrue(rows[0][0].startswith("* "), rows[0][0])
        self.assertIn("[older page]", rows[0][0])
        # And it is not also still down in the history block.
        self.assertEqual(len([r for r in rows if "older.example.com" in r[0]]), 1)

    def test_pinning_a_bookmark_takes_it_out_of_the_link_block(self):
        self.write_pins(
            ("https://zeta.example.com/docs", "Zeta docs", "xdg-open https://zeta.example.com/docs")
        )
        rows = self.candidates()
        zeta = [row for row in rows if "Zeta docs" in row[0]]
        self.assertEqual(len(zeta), 1)
        self.assertEqual(self.tag_of(zeta[0]), "#pin")

    def test_a_pin_outlives_the_row_it_was_made_from(self):
        # Nothing in history or the snippets points here any more.
        self.write_pins(
            ("https://gone.example.com/doc", "long gone", "xdg-open 'https://gone.example.com/doc'")
        )
        rows = self.candidates()
        self.assertIn("[long gone]", rows[0][0])
        self.assertEqual(rows[0][1], "xdg-open 'https://gone.example.com/doc'")

    def test_toggle_pins_then_unpins_the_same_row(self):
        row = self.candidates()[0]
        self.assertEqual(self.tag_of(row), "#history")

        run_script(self.workdir.name, dbs=[self.db], args=["--toggle-pin", "\t".join(row)])
        after = self.candidates()
        self.assertEqual(self.tag_of(after[0]), "#pin")
        self.assertIn("[recent page]", after[0][0])

        run_script(
            self.workdir.name, dbs=[self.db], args=["--toggle-pin", "\t".join(after[0])]
        )
        self.assertEqual(self.tag_of(self.candidates()[0]), "#history")

    def test_hidden_columns_carry_the_untruncated_title_and_url(self):
        long_title = "a very long tab title that the display column has to cut short " * 2
        long_url = "https://long.example.com/" + "segment/" * 20
        firefox_db(self.db, [(long_url, long_title, 300)])
        row = self.candidates()[0]
        # Display is truncated, the hidden columns are not, so a pin made from
        # this row stores the real title and url rather than "...".
        self.assertIn("...", row[0])
        self.assertEqual(row[2], " ".join(long_title.split()))
        self.assertEqual(row[3], long_url)


class SearchTest(unittest.TestCase):
    """--query ranks the whole corpus rather than the recent few hundred rows,
    which is what fzf used to filter. See test_vimium_rank.py for the ranking
    itself; these are the wiring around it."""

    def setUp(self):
        self.workdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.workdir.cleanup)
        self.path = Path(self.workdir.name)

    def search(self, query, dbs=(), **env):
        return run_script(self.workdir.name, dbs, args=["--query", query], **env)

    def titles(self, rows):
        return [row[0].split("[", 1)[1].split("]", 1)[0] for row in rows]

    def tag_of(self, row):
        return row[0].rsplit("  ", 1)[-1].strip()

    def test_a_scattered_subsequence_is_not_a_hit(self):
        # The bug this replaced fzf for: every letter of "triage" is in the
        # second title, in order, and none of them spell it.
        db = self.path / "places.sqlite"
        firefox_db(db, [
            ("https://linear.app/team/DEVOPS/triage", "Dev Ops Triage", 300),
            ("https://linear.app/issue/E-1/x", "conTaineR snapshot And restore", 290),
        ])
        rows = self.search("linear triage", dbs=[db])
        self.assertEqual(self.titles(rows), ["Dev Ops Triage"])

    def test_a_row_past_the_history_limit_is_still_found(self):
        # The list before anything is typed holds one row; the search still
        # reaches the other twenty, which is the reach the picker was missing.
        db = self.path / "places.sqlite"
        firefox_db(db, [
            ("https://e.example.com/%d" % n, "page %d" % n, 100 + n) for n in range(20)
        ] + [("https://needle.example.com/", "the needle", 1)])
        listed = run_script(self.workdir.name, [db], LINK_HISTORY_LIMIT="1")
        self.assertNotIn("the needle", self.titles(listed))
        rows = self.search("needle", dbs=[db], LINK_HISTORY_LIMIT="1")
        self.assertEqual(self.titles(rows), ["the needle"])

    def test_browser_bookmarks_join_the_corpus(self):
        db = self.path / "places.sqlite"
        firefox_db(db, [("https://a.example.com/", "unrelated", 300)])
        bookmark_table(db, [("https://saved.example.com/doc", "the saved doc")])
        rows = self.search("saved", dbs=[db])
        self.assertEqual(self.titles(rows), ["the saved doc"])
        self.assertEqual(self.tag_of(rows[0]), "#mark")

    def test_bookmarks_can_be_turned_off(self):
        db = self.path / "places.sqlite"
        firefox_db(db, [("https://a.example.com/", "unrelated", 300)])
        bookmark_table(db, [("https://saved.example.com/doc", "the saved doc")])
        self.assertEqual(self.search("saved", dbs=[db], LINK_BOOKMARKS="0"), [])

    # A places file with no bookmark tables must not take its history with it.
    def test_a_profile_without_bookmark_tables_still_gives_history(self):
        db = self.path / "places.sqlite"
        firefox_db(db, [("https://a.example.com/", "findable", 300)])
        self.assertEqual(self.titles(self.search("findable", dbs=[db])), ["findable"])

    def test_snippets_are_searched_too(self):
        rows = self.search("Zeta")
        self.assertEqual(self.tag_of(rows[0]), "#link")
        self.assertIn("Zeta docs", self.titles(rows))

    def test_a_pin_sits_above_the_ranking(self):
        db = self.path / "places.sqlite"
        firefox_db(db, [("https://exact.example.com/needle", "needle", 300)])
        pins_file(self.workdir.name).write_text(
            "\t".join([
                "https://pinned.example.com/",
                "needle in a much longer pinned title",
                "xdg-open 'https://pinned.example.com/'",
            ]) + "\n"
        )
        rows = self.search("needle", dbs=[db])
        self.assertEqual(self.tag_of(rows[0]), "#pin")
        self.assertEqual(len(rows), 2)

    def test_a_tag_narrows_without_being_searched_for(self):
        db = self.path / "places.sqlite"
        firefox_db(db, [("https://a.example.com/zeta", "zeta the page", 300)])
        self.assertEqual(self.tag_of(self.search("#link zeta", dbs=[db])[0]), "#link")
        self.assertEqual(self.titles(self.search("#history zeta", dbs=[db])),
                         ["zeta the page"])

    def test_an_empty_query_gives_the_default_list(self):
        db = self.path / "places.sqlite"
        firefox_db(db, [("https://a.example.com/", "A", 300)])
        self.assertEqual(self.search("", dbs=[db]), run_script(self.workdir.name, [db]))

    def test_a_tag_alone_filters_the_default_list(self):
        db = self.path / "places.sqlite"
        firefox_db(db, [("https://a.example.com/", "A", 300)])
        rows = self.search("#link", dbs=[db])
        self.assertTrue(rows)
        self.assertEqual({self.tag_of(row) for row in rows}, {"#link"})

    def test_the_result_count_is_capped(self):
        db = self.path / "places.sqlite"
        firefox_db(db, [
            ("https://e.example.com/needle/%d" % n, "needle %d" % n, 100 + n)
            for n in range(30)
        ])
        self.assertEqual(len(self.search("needle", dbs=[db], LINK_SEARCH_LIMIT="5")), 5)

    def test_the_corpus_is_cached_and_reused(self):
        db = self.path / "places.sqlite"
        firefox_db(db, [("https://a.example.com/needle", "needle", 300)])
        self.search("needle", dbs=[db])
        corpus = self.path / "corpus"
        self.assertTrue(corpus.exists())
        # Rewritten by hand: the next search must answer out of it rather than
        # go back to the database.
        corpus.write_text("h\thistory\t300\thttps://cached.example.com/\tcached needle\n")
        self.assertEqual(self.titles(self.search("needle", dbs=[db])), ["cached needle"])

    def test_a_moved_database_rebuilds_the_cache(self):
        db = self.path / "places.sqlite"
        firefox_db(db, [("https://a.example.com/needle", "first needle", 300)])
        self.search("needle", dbs=[db])
        firefox_db(db, [("https://b.example.com/needle", "second needle", 300)])
        self.assertEqual(self.titles(self.search("needle", dbs=[db])), ["second needle"])


if __name__ == "__main__":
    unittest.main()
