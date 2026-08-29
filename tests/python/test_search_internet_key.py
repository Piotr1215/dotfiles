import importlib.util
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

SCRIPT = Path(__file__).parents[2] / "scripts" / "__search_internet.py"


def load_module():
    spec = importlib.util.spec_from_file_location("search_internet", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ResolveApiKeyTest(unittest.TestCase):
    """The tmux popup that runs this has no direnv, so the env var is absent."""

    def setUp(self):
        self.saved = {
            name: os.environ.get(name)
            for name in ("PPLX_API_KEY", "PASSWORD_STORE_DIR", "PATH", "PPLX_PASS_ENTRY")
        }
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(self.restore)
        self.root = Path(self.tmp.name)

    def restore(self):
        for name, value in self.saved.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value

    def stub_gpg(self, body):
        bindir = self.root / "bin"
        bindir.mkdir(exist_ok=True)
        gpg = bindir / "gpg"
        gpg.write_text("#!/usr/bin/env bash\n" + body + "\n")
        gpg.chmod(0o755)
        os.environ["PATH"] = f"{bindir}:{self.saved['PATH']}"

    def test_env_wins_over_the_store(self):
        os.environ["PPLX_API_KEY"] = "from-env"
        self.stub_gpg('echo from-store')
        self.assertEqual(load_module().resolve_api_key(), "from-env")

    def test_falls_back_to_the_pass_entry(self):
        os.environ.pop("PPLX_API_KEY", None)
        os.environ["PASSWORD_STORE_DIR"] = str(self.root / "store")
        self.stub_gpg(
            'test "$3" = "%s/store/work/PPLX_API_KEY.gpg" || exit 2\n'
            "printf 'from-store\\n'" % self.root
        )
        self.assertEqual(load_module().resolve_api_key(), "from-store")

    def test_entry_is_overridable(self):
        os.environ.pop("PPLX_API_KEY", None)
        os.environ["PASSWORD_STORE_DIR"] = str(self.root / "store")
        os.environ["PPLX_PASS_ENTRY"] = "personal/PPLX_API_KEY"
        self.stub_gpg(
            'test "$3" = "%s/store/personal/PPLX_API_KEY.gpg" || exit 2\n'
            "printf 'other-store\\n'" % self.root
        )
        self.assertEqual(load_module().resolve_api_key(), "other-store")

    def test_a_failed_decrypt_returns_nothing(self):
        os.environ.pop("PPLX_API_KEY", None)
        os.environ["PASSWORD_STORE_DIR"] = str(self.root / "store")
        self.stub_gpg("exit 2")
        self.assertEqual(load_module().resolve_api_key(), "")

    def test_a_missing_gpg_returns_nothing(self):
        os.environ.pop("PPLX_API_KEY", None)
        os.environ["PASSWORD_STORE_DIR"] = str(self.root / "store")
        os.environ["PATH"] = str(self.root / "empty")
        self.assertEqual(load_module().resolve_api_key(), "")


if __name__ == "__main__":
    unittest.main()
