"""Exercise M-x itself without opening a popup or switching Piotr's client."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[2]


class FileOpenerLatencyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.home = self.root / "home"
        for name in ("dev/dotfiles", "loft", ".config/nvim", ".claude"):
            (self.home / name).mkdir(parents=True)
        (self.home / "dev/dotfiles/scripts").symlink_to(REPO / "scripts")
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=f"{self.bin}:{os.environ['PATH']}",
                        TMUX="", TERM="dumb", TEST_ROOT=str(self.root),
                        FILE_OPENER_CACHE_FILE=str(self.root / "cache"))
        self.stub("tmux", """
case "$1" in
  list-sessions) printf 'task\n' ;;
  list-panes)
    if [[ " $* " == *' -a '* ]]; then printf 'task|triage||\n'
    else printf '1|triage\n'; fi ;;
  switch-client) printf '%s\n' "$*" > "$TEST_ROOT/switch" ;;
esac
""")
        self.stub("zoxide", ":")
        self.stub("fd", """
touch "$TEST_ROOT/scanning"
sleep "${SCAN_DELAY:-0}"
if [[ -f "$TEST_ROOT/scan-fails" ]]; then exit 1; fi
printf '%s\0' "$HOME/dev/a file.md"
""")
        (self.home / "dev/a file.md").write_text("file with a space")

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\nset -e\n" + body + "\n")
        path.chmod(0o755)

    def run_script(self, name, *, timeout=5, **env):
        # Kill only this test's process group, including an unfinished scan.
        # Files avoid capture pipes held open by descendants after fzf exits.
        with (self.root / "stdout").open("w+") as out, \
                (self.root / "stderr").open("w+") as err:
            process = subprocess.Popen(
                ["bash", str(REPO / "scripts" / name)], env=self.env | env,
                stdout=out, stderr=err, start_new_session=True)
            started = time.monotonic()
            try:
                process.wait(timeout=timeout)
                elapsed = time.monotonic() - started
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            out.seek(0)
            err.seek(0)
            self.assertEqual(process.returncode, 0, err.read())
            return out.read(), elapsed

    def picker(self, action):
        self.stub("fzf", """
IFS= read -r choice
# Ensure the file scan is in progress when the user selects or cancels.
for ((i=0; i<200; i++)); do
  [[ ! -f "$TEST_ROOT/scanning" ]] || break
  sleep 0.005
done
[[ -f "$TEST_ROOT/scanning" ]]
""" + action)

    def test_session_switch_does_not_wait_for_cold_scan(self):
        self.picker('printf "%s\\n" "$choice"')
        _, elapsed = self.run_script("__file_opener.sh", timeout=2, SCAN_DELAY="4")
        self.assertLess(elapsed, 2)
        self.assertEqual((self.root / "switch").read_text(),
                         "switch-client -t =task\n")
        self.assertFalse((self.root / "cache").exists())

    def test_cancel_does_not_wait_for_cold_scan(self):
        self.picker("exit 130")
        _, elapsed = self.run_script("__file_opener.sh", timeout=2, SCAN_DELAY="4")
        self.assertLess(elapsed, 2)
        self.assertFalse((self.root / "switch").exists())

    def test_completed_scan_caches_paths_with_spaces(self):
        out, _ = self.run_script("__file_opener_choices.sh")
        expected = str(self.home / "dev/a file.md") + "\n"
        self.assertTrue(out.endswith(expected), out)
        self.assertEqual((self.root / "cache").read_text(), expected)
        self.assertEqual(list(self.root.glob("cache.*")), [])

    def test_fresh_cache_skips_scan(self):
        (self.root / "cache").write_text("/cached/file\n")
        out, _ = self.run_script("__file_opener_choices.sh")
        self.assertTrue(out.endswith("/cached/file\n"), out)
        self.assertFalse((self.root / "scanning").exists())

    def test_failed_scan_preserves_stale_cache(self):
        cache = self.root / "cache"
        cache.write_text("/cached/file\n")
        old = time.time() - 120
        os.utime(cache, (old, old))
        (self.root / "scan-fails").touch()
        out, _ = self.run_script("__file_opener_choices.sh")
        self.assertTrue(out.endswith("/cached/file\n"), out)
        self.assertEqual(cache.read_text(), "/cached/file\n")
        self.assertEqual(list(self.root.glob("cache.*")), [])


if __name__ == "__main__":
    unittest.main()
