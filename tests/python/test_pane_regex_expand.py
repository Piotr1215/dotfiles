import json
import runpy
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).parents[2]
AUTOKEY_DIR = ROOT / ".config" / "autokey" / "data" / "My Phrases"
AUTOKEY_JSON = AUTOKEY_DIR / ".pane_regex_expand.json"
AUTOKEY_SCRIPT = AUTOKEY_DIR / "pane_regex_expand.py"
TMUX_CONFIG = ROOT / ".tmux.conf"
OLD_SCRIPT = ROOT / "scripts" / "__pane_regex_expand.py"


class PaneRegexIntegrationTests(unittest.TestCase):
    def test_autokey_entry_reserves_the_dynamic_prefix(self):
        config = json.loads(AUTOKEY_JSON.read_text())

        self.assertEqual(config["abbreviation"]["abbreviations"], [";;^"])
        self.assertTrue(config["abbreviation"]["immediate"])
        self.assertTrue(config["abbreviation"]["triggerInside"])
        self.assertFalse(config["abbreviation"]["backspace"])
        self.assertTrue(config["omitTrigger"])

    def test_autokey_launches_the_plugin_path_published_by_tmux(self):
        with (
            mock.patch("subprocess.check_output", return_value="/tmp/pane_regex.py\n"),
            mock.patch("subprocess.Popen") as popen,
        ):
            runpy.run_path(str(AUTOKEY_SCRIPT))

        popen.assert_called_once_with(["/tmp/pane_regex.py", "3"])

    def test_autokey_does_not_launch_when_plugin_is_not_loaded(self):
        with (
            mock.patch("subprocess.check_output", return_value=""),
            mock.patch("subprocess.Popen") as popen,
        ):
            runpy.run_path(str(AUTOKEY_SCRIPT))

        popen.assert_not_called()

    def test_tmux_loads_the_local_plugin(self):
        config = TMUX_CONFIG.read_text()

        self.assertIn("$HOME/dev/tmux-pane-regex/tmux-pane-regex.tmux", config)

    def test_dotfiles_no_longer_carry_a_second_extractor_copy(self):
        self.assertFalse(OLD_SCRIPT.exists())


if __name__ == "__main__":
    unittest.main()
