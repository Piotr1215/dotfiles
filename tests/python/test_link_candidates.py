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
    conn.execute("create table moz_places (url text, title text, last_visit_date integer)")
    conn.executemany(
        "insert into moz_places values (?, ?, ?)",
        [(url, title, int(when * 1000000)) for url, title, when in rows],
    )
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


def run_script(workdir, dbs, **env_overrides):
    snippet_file = Path(workdir) / "pet-links.toml"
    snippet_file.write_text(SNIPPETS)
    env = {
        **os.environ,
        "PET_SNIPPET_FILE": str(snippet_file),
        "LINK_HISTORY_DBS": ":".join(str(db) for db in dbs),
    }
    env.update(env_overrides)
    result = subprocess.run(
        ["python3", str(SCRIPT)], text=True, capture_output=True, env=env, check=True
    )
    rows = []
    for line in result.stdout.splitlines():
        display, command = line.split("\t")
        rows.append((display, command))
    return rows


class LinkCandidatesTest(unittest.TestCase):
    def setUp(self):
        self.workdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.workdir.cleanup)
        self.path = Path(self.workdir.name)

    def candidates(self, firefox_rows=(), chrome_rows=(), **env):
        dbs = []
        if firefox_rows:
            db = self.path / "places.sqlite"
            firefox_db(db, firefox_rows)
            dbs.append(db)
        if chrome_rows:
            db = self.path / "History"
            chrome_db(db, chrome_rows)
            dbs.append(db)
        return run_script(self.workdir.name, dbs, **env)

    def test_snippets_come_first_sorted_and_tagged(self):
        rows = self.candidates(firefox_rows=[("https://a.example.com/", "A", 100)])
        self.assertIn("[Alpha anchor]", rows[0][0])
        self.assertIn("#link", rows[0][0])
        self.assertIn("[Zeta docs]", rows[1][0])
        self.assertIn("#history", rows[2][0])

    def test_snippet_command_survives_shell_escapes(self):
        rows = self.candidates()
        self.assertEqual(
            rows[0][1],
            r"xdg-open https://alpha.example.com/page/\#:\~:text\=hit",
        )
        # The display drops the escapes, the command keeps them.
        self.assertIn("https://alpha.example.com/page/#:~:text=hit", rows[0][0])

    def test_history_row_matching_a_snippet_is_dropped(self):
        rows = self.candidates(
            firefox_rows=[("https://zeta.example.com/docs", "Zeta docs", 100)]
        )
        self.assertEqual([row for row in rows if "#history" in row[0]], [])

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
        history = [row for row in rows if "#history" in row[0]]
        self.assertEqual(len(history), 1)
        self.assertIn("[Keep me]", history[0][0])

    def test_same_title_on_one_host_collapses(self):
        rows = self.candidates(
            firefox_rows=[
                ("https://github.com/org/repo/pull/1", "fix: the thing", 100),
                ("https://github.com/org/repo/pull/1/changes", "fix: the thing", 90),
            ]
        )
        self.assertEqual(len([row for row in rows if "#history" in row[0]]), 1)

    def test_per_host_cap_keeps_a_busy_host_from_taking_over(self):
        rows = self.candidates(
            firefox_rows=[
                ("https://github.com/org/repo/pull/1", "first pr", 100),
                ("https://github.com/org/repo/pull/2", "second pr", 90),
                ("https://other.example.com/x", "other page", 80),
            ],
            LINK_HISTORY_PER_HOST="1",
        )
        history = [row for row in rows if "#history" in row[0]]
        self.assertEqual(len(history), 2)
        self.assertIn("[first pr]", history[0][0])
        self.assertIn("[other page]", history[1][0])

    def test_history_limit_and_kill_switch(self):
        firefox_rows = [
            ("https://one.example.com/", "one", 100),
            ("https://two.example.com/", "two", 90),
        ]
        capped = self.candidates(firefox_rows=firefox_rows, LINK_HISTORY_LIMIT="1")
        self.assertEqual(len([row for row in capped if "#history" in row[0]]), 1)

        off = self.candidates(firefox_rows=firefox_rows, LINK_HISTORY="0")
        self.assertEqual([row for row in off if "#history" in row[0]], [])

    def test_history_command_is_quoted_for_eval(self):
        rows = self.candidates(
            chrome_rows=[("https://ci.example.com/job?id=7&x=1", "Job 7", 100)]
        )
        history = [row for row in rows if "#history" in row[0]]
        self.assertEqual(history[0][1], "xdg-open 'https://ci.example.com/job?id=7&x=1'")

    def test_untitled_rows_are_skipped(self):
        rows = self.candidates(
            firefox_rows=[
                ("https://blank.example.com/", "", 100),
                ("https://good.example.com/", "Good", 90),
            ]
        )
        history = [row for row in rows if "#history" in row[0]]
        self.assertEqual(len(history), 1)
        self.assertIn("[Good]", history[0][0])


if __name__ == "__main__":
    unittest.main()
