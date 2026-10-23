import json
import os
import runpy
import subprocess
import tempfile
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
        def output(command, **_):
            return "/tmp/pane_regex.py\n" if command[0] == "tmux" else "%7\n"

        with (
            mock.patch("subprocess.check_output", side_effect=output),
            mock.patch("subprocess.Popen") as popen,
        ):
            runpy.run_path(str(AUTOKEY_SCRIPT))

        self.assertEqual(
            popen.call_args.args[0], ["/tmp/pane_regex.py", "3", "--pane", "%7"]
        )

    def test_autokey_searches_the_focused_pane_not_the_one_it_inherited(self):
        # AutoKey restarted from an agent pane keeps that pane's TMUX_PANE, and
        # tmux answers a bare pane lookup from it. The real pane lib must pick
        # the client with the newest input, and the plugin must not inherit it.
        with tempfile.TemporaryDirectory() as stub_dir:
            stub = Path(stub_dir) / "tmux"
            stub.write_text(
                "#!/usr/bin/env bash\n"
                'case "$1" in\n'
                "show-option) echo /tmp/pane_regex.py ;;\n"
                "list-clients) printf '%s\\n' '100 %51' '200 %7' ;;\n"
                "esac\n"
            )
            stub.chmod(0o755)
            inherited = {
                "PATH": f"{stub_dir}:{os.environ['PATH']}",
                "TMUX": "/tmp/tmux-1000/default,7948,17",
                "TMUX_PANE": "%51",
            }
            # check_output runs on Popen too, so only the plugin launch is caught.
            real_popen = subprocess.Popen
            launches = []

            def popen(command, *args, **kwargs):
                if command[0] != "/tmp/pane_regex.py":
                    return real_popen(command, *args, **kwargs)
                launches.append((command, kwargs))
                return mock.Mock()

            with (
                mock.patch.dict(os.environ, inherited),
                mock.patch("subprocess.Popen", side_effect=popen),
            ):
                runpy.run_path(str(AUTOKEY_SCRIPT))

        self.assertEqual(len(launches), 1)
        command, kwargs = launches[0]
        self.assertEqual(command, ["/tmp/pane_regex.py", "3", "--pane", "%7"])
        self.assertNotIn("TMUX_PANE", kwargs["env"])
        self.assertNotIn("TMUX", kwargs["env"])

    def test_autokey_leaves_the_pane_to_the_plugin_without_a_client(self):
        def output(command, **_):
            return "/tmp/pane_regex.py\n" if command[0] == "tmux" else ""

        with (
            mock.patch("subprocess.check_output", side_effect=output),
            mock.patch("subprocess.Popen") as popen,
        ):
            runpy.run_path(str(AUTOKEY_SCRIPT))

        self.assertEqual(popen.call_args.args[0], ["/tmp/pane_regex.py", "3"])

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
