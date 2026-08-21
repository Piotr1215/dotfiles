"""The port in __lib_vimium_rank.py against Vimium C's own numbers.

Every float below was produced by loading background/completion_utils.js out of
the installed extension (Vimium C 2.12.2) and calling its ranking directly, so
these are not what the port is expected to do, they are what the extension
does. A wider differential run over 400 rows of real history and a dozen
queries agreed on every value; these are the cases worth keeping.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "scripts"))

import __lib_vimium_rank as vimium  # noqa: E402

# A fixed clock, so the recency cases below do not decay as they age.
NOW_MS = 1755000000000.0

TRIAGE_URL = "https://linear.app/loft/team/DEVOPS/triage"
TRIAGE_TITLE = "Dev Ops › Triage (3)"

# The row fzf's fuzzy match used to return for "triage": the letters are there
# in order, scattered, and none of them spell the word.
SCATTERED_URL = (
    "https://linear.app/loft/issue/ENGQA-1369/"
    "ginkgo-e2e-container-snapshot-and-restore-via-cli"
)
SCATTERED_TITLE = "Inbox › ENGQA-1369 Ginkgo E2E: container:// snapshot and restore via CLI"


def ranker(query, now_ms=NOW_MS):
    return vimium.Ranker(query.split(), now_ms)


class ShortenUrlTest(unittest.TestCase):
    def test_drops_the_scheme(self):
        self.assertEqual(vimium.shorten_url(TRIAGE_URL), "linear.app/loft/team/DEVOPS/triage")
        self.assertEqual(vimium.shorten_url("http://a.io/b"), "a.io/b")

    def test_drops_one_trailing_slash(self):
        self.assertEqual(vimium.shorten_url("https://a.io/b/"), "a.io/b")

    # The slash after the scheme is the scheme's, so there is none to drop.
    def test_leaves_a_bare_scheme_alone(self):
        self.assertEqual(vimium.shorten_url("https://"), "https://")

    def test_leaves_other_schemes_alone(self):
        self.assertEqual(vimium.shorten_url("file:///tmp/x"), "file:///tmp/x")


class MatchTest(unittest.TestCase):
    def test_every_term_has_to_land(self):
        self.assertTrue(ranker("linear triage").matches(
            vimium.shorten_url(TRIAGE_URL), TRIAGE_TITLE))

    # The whole point of the port. fzf matched this row on both terms; Vimium C
    # does not, because neither word is in it.
    def test_a_scattered_subsequence_is_not_a_match(self):
        self.assertFalse(ranker("linear triage").matches(
            vimium.shorten_url(SCATTERED_URL), SCATTERED_TITLE))

    def test_a_lowercase_term_ignores_case(self):
        self.assertTrue(ranker("devops").matches(
            vimium.shorten_url(TRIAGE_URL), TRIAGE_TITLE))

    # A term carrying a capital is matched case sensitively, which is how
    # DEVOPS narrows without also hitting devops in a url.
    def test_a_term_with_a_capital_does_not(self):
        self.assertFalse(ranker("DEVOPS").matches(
            "linear.app/loft/team/devops/triage", "dev ops triage"))

    def test_matches_in_reads_one_string(self):
        self.assertTrue(ranker("linear triage").matches_in(TRIAGE_URL + "\n" + TRIAGE_TITLE))
        self.assertFalse(ranker("linear absent").matches_in(TRIAGE_URL + "\n" + TRIAGE_TITLE))


class WordRelevancyTest(unittest.TestCase):
    def assertScore(self, got, want):
        self.assertAlmostEqual(got, want, places=12)

    def test_two_terms_across_url_and_title(self):
        self.assertScore(
            ranker("linear triage").word_relevancy(
                vimium.shorten_url(TRIAGE_URL), TRIAGE_TITLE),
            0.27647058823529413,
        )

    # "triage" is a whole word in both, and the title is short, so the title
    # scores higher and takes the row outright.
    def test_the_better_scoring_title_wins_outright(self):
        self.assertScore(
            ranker("triage").word_relevancy(
                vimium.shorten_url(TRIAGE_URL), TRIAGE_TITLE),
            0.3,
        )

    # Nothing in the title, so the url's score is halved.
    def test_a_url_only_hit_is_halved(self):
        self.assertScore(
            ranker("devops").word_relevancy(
                vimium.shorten_url(TRIAGE_URL), TRIAGE_TITLE),
            0.08823529411764706,
        )

    def test_no_hit_anywhere_scores_zero(self):
        self.assertScore(ranker("triage").word_relevancy("example.com/x", ""), 0.0)


class RecencyTest(unittest.TestCase):
    def test_a_page_seen_now_peaks(self):
        self.assertAlmostEqual(ranker("x").recency(NOW_MS), 0.666446, places=6)

    def test_older_than_the_window_scores_zero(self):
        stale = NOW_MS - vimium.RECENCY_WINDOW_MS - 1
        self.assertEqual(ranker("x").recency(stale), 0.0)

    # Quadratic, so the middle of the window is a quarter of the peak, not half.
    def test_the_curve_is_quadratic(self):
        middle = NOW_MS - vimium.RECENCY_WINDOW_MS / 2
        self.assertAlmostEqual(ranker("x").recency(middle), 0.25 * vimium.RECENCY_PEAK, places=12)

    def test_a_visit_time_in_the_future_scores_zero(self):
        self.assertEqual(ranker("x").recency(NOW_MS + vimium.RECENCY_WINDOW_MS), 0.0)


class RelevancyTest(unittest.TestCase):
    # Recency beats the word score here, so the two are averaged.
    def test_recency_lifts_a_weak_word_score(self):
        self.assertAlmostEqual(
            ranker("linear triage").relevancy(
                vimium.shorten_url(TRIAGE_URL), TRIAGE_TITLE, NOW_MS),
            0.47145829411764706,
            places=12,
        )

    # Once the word score already beats recency it stands alone, so a page
    # visited a month ago is not punished for it.
    def test_a_strong_word_score_stands_alone(self):
        stale = NOW_MS - vimium.RECENCY_WINDOW_MS - 1
        r = ranker("triage")
        text = vimium.shorten_url(TRIAGE_URL)
        self.assertAlmostEqual(r.relevancy(text, TRIAGE_TITLE, stale), 0.3, places=12)


if __name__ == "__main__":
    unittest.main()
