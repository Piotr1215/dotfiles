import importlib.util
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

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


if __name__ == "__main__":
    unittest.main()
