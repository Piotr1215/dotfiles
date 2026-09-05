import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).parents[2]
SCRIPT = ROOT / "scripts" / "__pane_regex_expand.py"
AUTOKEY_JSON = (
    ROOT / ".config" / "autokey" / "data" / "My Phrases" / ".pane_regex_expand.json"
)
AUTOKEY_SCRIPT = (
    ROOT / ".config" / "autokey" / "data" / "My Phrases" / "pane_regex_expand.py"
)


def load_module():
    spec = importlib.util.spec_from_file_location("pane_regex_expand", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class PaneRegexMatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_exact_line_uses_latest_match(self):
        match = self.mod.find_latest_match("site\nother\nsite\n", r"^site$")

        self.assertIsNotNone(match)
        self.assertEqual(match.text, "site")
        self.assertEqual(match.start_line, 2)
        self.assertEqual(match.end_line, 2)

    def test_occurrence_offset_selects_an_older_highlight(self):
        text = "first screenshot line\nother\nnewest screenshot line\n"

        match = self.mod.find_latest_match(text, r"^screen$", occurrence=1)

        self.assertIsNotNone(match)
        self.assertEqual(match.text, "first screenshot line")

    def test_short_anchored_phrase_selects_the_whole_latest_line(self):
        text = (
            "The stable old result\n"
            "other\n"
            "The stable build now passes the isolated Tab path.\n"
        )

        match = self.mod.find_latest_match(text, r"^The stable$")

        self.assertIsNotNone(match)
        self.assertEqual(
            match.text, "The stable build now passes the isolated Tab path."
        )
        self.assertEqual(match.start_line, 2)

    def test_short_anchored_word_may_be_anywhere_in_the_line(self):
        text = "before\nThe stable build now passes.\nafter\n"

        match = self.mod.find_latest_match(text, r"^stable$")

        self.assertIsNotNone(match)
        self.assertEqual(match.text, "The stable build now passes.")

    def test_unfinished_short_form_already_highlights_the_containing_line(self):
        text = "before\nI’m checking the exact live popup state.\nafter\n"

        match = self.mod.find_latest_match(text, r"^checking")

        self.assertIsNotNone(match)
        self.assertEqual(match.text, "I’m checking the exact live popup state.")

    def test_codex_bullet_is_not_part_of_a_selected_line(self):
        text = "• The stable build now passes the isolated Tab path.\n"

        match = self.mod.find_latest_match(text, r"^The stable$")

        self.assertIsNotNone(match)
        self.assertEqual(
            match.text, "The stable build now passes the isolated Tab path."
        )

    def test_dot_matches_newlines_and_keeps_boundaries(self):
        text = "before\nthe first line\nmiddle line\nlast line too\nafter\n"

        match = self.mod.find_latest_match(text, r"^the.*too$")

        self.assertIsNotNone(match)
        self.assertEqual(match.text, "the first line\nmiddle line\nlast line too")
        self.assertEqual(match.start_line, 1)
        self.assertEqual(match.end_line, 3)

    def test_range_words_are_inclusive_locators_not_line_anchors(self):
        text = "prefix checking one\nmiddle\nending selector suffix\n"

        match = self.mod.find_latest_match(text, r"^checking.*selector$")

        self.assertIsNotNone(match)
        self.assertEqual(match.text, "checking one\nmiddle\nending selector")

    def test_open_ended_range_starts_at_match_and_stops_at_logical_line_end(self):
        text = "prefix screenshot text to reuse\nlater output\n"

        match = self.mod.find_latest_match(text, r"^screen.*$")

        self.assertIsNotNone(match)
        self.assertEqual(match.text, "screenshot text to reuse")

    def test_double_dollar_is_short_for_match_through_line_end(self):
        text = "prefix screenshot text to reuse\nlater output\n"

        match = self.mod.find_latest_match(text, r"^screen$$")

        self.assertIsNotNone(match)
        self.assertEqual(match.text, "screenshot text to reuse")

    def test_range_search_uses_the_latest_viable_start_locator(self):
        text = "checking old selector\nchecking newest selector\n"

        match = self.mod.find_latest_match(text, r"^checking.*selector$")

        self.assertIsNotNone(match)
        self.assertEqual(match.text, "checking newest selector")

    def test_native_highlight_uses_the_line_locator(self):
        self.assertEqual(self.mod.native_highlight_pattern(r"^checking"), "checking")
        self.assertEqual(self.mod.native_highlight_pattern(r"^checking$"), "checking")

    def test_native_highlight_uses_the_start_of_a_multiline_range(self):
        self.assertEqual(
            self.mod.native_highlight_pattern(r"^checking.*selector$"),
            "checking.*selector",
        )

    def test_native_highlight_covers_an_open_ended_line_from_the_match(self):
        self.assertEqual(
            self.mod.native_highlight_pattern(r"^screen.*$"),
            r"(screen.*[^[:space:]]|screen)",
        )

    def test_native_highlight_expands_double_dollar_shorthand(self):
        self.assertEqual(
            self.mod.native_highlight_pattern(r"^screen$$"),
            r"(screen.*[^[:space:]]|screen)",
        )

    def test_multiline_native_highlight_covers_the_first_line_tail(self):
        match = self.mod.Match("checking one\nmiddle\nending selector", 1, 3)

        self.assertEqual(
            self.mod.native_highlight_pattern(r"^checking.*selector$", match),
            r"(checking.*[^[:space:]]|checking)",
        )

    def test_native_highlight_accepts_smart_prose_apostrophes(self):
        self.assertEqual(self.mod.native_highlight_pattern(r"^I'm$"), "I['’]m")

    def test_search_starts_at_latest_output_and_moves_up(self):
        text = "the old\nold too\nthe newest\nnewest too\nafter\n"

        match = self.mod.find_latest_match(text, r"^the.*too$")

        self.assertIsNotNone(match)
        self.assertEqual(match.text, "the newest\nnewest too")

    def test_straight_apostrophe_matches_smart_prose_apostrophe(self):
        text = "I’m setting aside the memory.\nTab inserts it back into.\n"

        match = self.mod.find_latest_match(text, r"^I'm.*into\.$")

        self.assertIsNotNone(match)
        self.assertEqual(match.text, text.rstrip("\n"))

    def test_codex_display_margin_is_not_part_of_expansion(self):
        text = "  I’m setting aside the memory.\n    Tab inserts it too.\n"

        match = self.mod.find_latest_match(text, r"^I'm.*too\.$")

        self.assertIsNotNone(match)
        self.assertEqual(
            match.text, "I’m setting aside the memory.\nTab inserts it too."
        )

    def test_accept_erases_only_the_matcher_already_in_the_app(self):
        self.assertEqual(self.mod.inline_erase_count(3, "^"), 3)
        self.assertEqual(
            self.mod.inline_erase_count(3, "^the.*too$"), len(";;^the.*too$")
        )

    def test_query_typed_during_popup_start_is_recovered(self):
        captured = "text> ;;^the.*too$" + (" " * 60)

        query = self.mod.inline_query_from_capture(captured, len("text> ;;^the.*too$"))

        self.assertEqual(query, "^the.*too$")

    def test_recovered_query_uses_the_latest_trigger(self):
        captured = "old ;;^site$ then ;;^I'm.*to\\.$"

        query = self.mod.inline_query_from_capture(captured, len(captured))

        self.assertEqual(query, "^I'm.*to\\.$")

    def test_fzf_starts_with_the_recovered_query(self):
        command = self.mod.fzf_command(
            "%1", Path("/tmp/pane-regex-expand-test"), "^the.*too$"
        )

        self.assertIn("--query=^the.*too$", command)

    def test_fzf_records_live_updates_without_running_tmux_inline(self):
        command = self.mod.fzf_command("%1", Path("/tmp/pane-regex-expand-test"), "^")
        rendered = " ".join(command)

        self.assertIn("desired.new", rendered)
        self.assertIn("desired", rendered)
        self.assertNotIn("--update", rendered)

    def test_fzf_arrows_move_between_native_tmux_highlights(self):
        command = self.mod.fzf_command("%1", Path("/tmp/pane-regex-expand-test"), "^")
        rendered = " ".join(command)

        self.assertIn("up:execute-silent", rendered)
        self.assertIn("down:execute-silent", rendered)
        self.assertIn("--move %1 /tmp/pane-regex-expand-test older", rendered)
        self.assertIn("--move %1 /tmp/pane-regex-expand-test newer", rendered)

    def test_enter_keeps_the_match_selected_with_the_arrows(self):
        query = r"^screen$$"
        with tempfile.TemporaryDirectory(prefix="pane-regex-expand-test-") as name:
            state = Path(name)
            (state / "query").write_text(query)
            self.mod.write_match(state, query, self.mod.Match("older screen", 2, 2))

            with mock.patch.object(self.mod, "update") as update:
                action = self.mod.action_for_accept("%1", name, query, space=False)

        self.assertEqual(action, "accept")
        update.assert_not_called()

    def test_watcher_refresh_keeps_the_arrow_selected_occurrence(self):
        query = r"^screen$"
        captured = "older screenshot line\nnewer screenshot line\n"
        with tempfile.TemporaryDirectory(prefix="pane-regex-expand-test-") as name:
            state = Path(name)
            (state / "query").write_text(query)
            (state / "occurrence").write_text("1")
            completed = self.mod.subprocess.CompletedProcess([], 0, stdout=captured)

            with (
                mock.patch.object(self.mod, "tmux", return_value=completed),
                mock.patch.object(self.mod, "show_match") as show_match,
            ):
                match = self.mod.update("%1", name, query)

            stored = self.mod.read_match(state, query)

        self.assertEqual(match.text, "older screenshot line")
        self.assertEqual(stored, match)
        show_match.assert_called_once_with("%1", query, match, occurrence=1)

    def test_trailing_anchor_space_accepts_only_a_current_match(self):
        self.assertEqual(self.mod.space_action(r"^site$", has_match=True), "accept")
        self.assertEqual(self.mod.space_action(r"^site$", has_match=False), "no-match")
        self.assertEqual(self.mod.space_action(r"^kind of", has_match=False), "put( )")
        self.assertEqual(self.mod.space_action(r"^price\$", has_match=True), "put( )")


class PaneRegexAutoKeyTests(unittest.TestCase):
    def test_autokey_entry_reserves_the_dynamic_prefix(self):
        config = json.loads(AUTOKEY_JSON.read_text())

        self.assertEqual(config["abbreviation"]["abbreviations"], [";;^"])
        self.assertTrue(config["abbreviation"]["immediate"])
        self.assertTrue(config["abbreviation"]["triggerInside"])
        self.assertFalse(config["abbreviation"]["backspace"])
        self.assertTrue(config["omitTrigger"])

    def test_autokey_entry_launches_the_pane_regex_expander(self):
        source = AUTOKEY_SCRIPT.read_text()

        self.assertIn("__pane_regex_expand.py", source)
        self.assertIn("subprocess.Popen", source)


if __name__ == "__main__":
    unittest.main()
