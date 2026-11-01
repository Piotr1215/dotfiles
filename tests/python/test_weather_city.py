import importlib.util
import os
import unittest
from io import BytesIO
from pathlib import Path
from tempfile import TemporaryDirectory
from urllib.error import HTTPError, URLError

SCRIPT = Path(__file__).parents[2] / ".config" / "argos" / "weather.30m.py"


def load_module():
    spec = importlib.util.spec_from_file_location("weather", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GetCityTest(unittest.TestCase):
    """argos runs the applet with no direnv, so $CITY is usually absent."""

    def setUp(self):
        self.saved = os.environ.get("CITY")
        self.addCleanup(self.restore)
        tmp = TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.envrc = Path(tmp.name) / ".envrc"
        self.weather = load_module()
        self.weather.envrc_path = str(self.envrc)
        os.environ.pop("CITY", None)

    def restore(self):
        if self.saved is None:
            os.environ.pop("CITY", None)
        else:
            os.environ["CITY"] = self.saved

    def test_env_wins_over_the_envrc(self):
        os.environ["CITY"] = "Korinthos,GR"
        self.envrc.write_text("export CITY=MITTELBUCHEN\n")
        self.assertEqual(self.weather.get_city(), "Korinthos,GR")

    def test_falls_back_to_the_envrc_export(self):
        self.envrc.write_text(
            "_pass_export WEATHER_API_KEY personal/WEATHER_API_KEY\n"
            "export CITY=MITTELBUCHEN\n"
        )
        self.assertEqual(self.weather.get_city(), "MITTELBUCHEN")

    def test_quotes_are_stripped(self):
        self.envrc.write_text('export CITY="Bad Homburg,DE"\n')
        self.assertEqual(self.weather.get_city(), "Bad Homburg,DE")

    def test_the_last_export_wins_as_in_bash(self):
        self.envrc.write_text("export CITY=Hanau\nexport CITY=Korinthos,GR\n")
        self.assertEqual(self.weather.get_city(), "Korinthos,GR")

    def test_a_commented_export_is_ignored(self):
        self.envrc.write_text("# export CITY=Hanau\n")
        with self.assertRaisesRegex(RuntimeError, "no export CITY= line"):
            self.weather.get_city()

    def test_a_missing_envrc_is_an_error(self):
        with self.assertRaisesRegex(RuntimeError, "CITY unset"):
            self.weather.get_city()


class FetchTest(unittest.TestCase):
    """argos reruns the applet every 30m, so one failed run shows for 30m. The
    first run after a boot lands seconds before the network is up."""

    def setUp(self):
        self.weather = load_module()
        self.weather.retry_delay = 0
        self.calls = 0

    def serve(self, *outcomes):
        def urlopen(url, timeout):
            outcome = outcomes[min(self.calls, len(outcomes) - 1)]
            self.calls += 1
            if isinstance(outcome, Exception):
                raise outcome
            return BytesIO(outcome)
        self.weather.urlopen = urlopen

    def test_waits_for_the_network_to_come_up(self):
        down = URLError("Temporary failure in name resolution")
        self.serve(down, down, b'{"name": "Mittelbuchen"}')
        self.assertEqual(self.weather.fetch("weather", "X", "KEY"), {"name": "Mittelbuchen"})
        self.assertEqual(self.calls, 3)

    def test_gives_up_when_the_network_stays_down(self):
        self.serve(URLError("Network is unreachable"))
        with self.assertRaisesRegex(RuntimeError, "weather: Network is unreachable") as caught:
            self.weather.fetch("weather", "X", "KEY")
        self.assertEqual(self.calls, self.weather.network_tries)
        self.assertNotIn("KEY", str(caught.exception))

    def test_a_server_refusal_is_final(self):
        self.serve(HTTPError("https://x", 401, "Unauthorized", None, None))
        with self.assertRaisesRegex(RuntimeError, "weather: HTTP 401 Unauthorized"):
            self.weather.fetch("weather", "X", "KEY")
        self.assertEqual(self.calls, 1)


if __name__ == "__main__":
    unittest.main()
