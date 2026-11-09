"""Exercise harness cleanup when a tmux command fails after startup."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
TMUX = shutil.which("tmux")
BATS = shutil.which("bats")


@unittest.skipUnless(TMUX and BATS, "tmux and bats are required")
class HarnessCleanupTest(unittest.TestCase):
    def test_failed_harnesses_stop_isolated_servers(self):
        cases = [
            (["bash", "tests/shell/tmux_float_binding_test.sh"], "float-bind-"),
            (["bats", "-f", "on a real tmux server", "tests/bats/tmux_float_step_test.bats"], "float-step-"),
            (["bash", "tests/shell/tmux_reading_margin_client_tests.sh"], "/socket"),
        ]
        for command, target in cases:
            with self.subTest(command=command), tempfile.TemporaryDirectory() as directory:
                tmp = Path(directory)
                wrapper = tmp / "tmux"
                wrapper.write_text('''#!/usr/bin/env python3
import json, os, subprocess, sys
args = sys.argv[1:]
socket = next(((args[i], args[i+1]) for i in range(len(args)-1) if args[i] in ("-L", "-S")), None)
if socket and "new-session" in args:
    result = subprocess.run([os.environ["REAL_TMUX"], *args])
    pid = subprocess.run([os.environ["REAL_TMUX"], *socket, "display-message", "-p", "#{pid}"], capture_output=True, text=True).stdout.strip()
    with open(os.environ["HARNESS_LOG"], "a") as log:
        log.write(json.dumps([socket, args, pid]) + "\\n")
    sys.exit(result.returncode)
elif socket and os.environ["HARNESS_TARGET"] in socket[1] and "kill-server" not in args and not (os.environ["HARNESS_TARGET"] == "float-step-" and "new-pane" in args) and not os.path.exists(os.environ["HARNESS_FAILED"]):
    open(os.environ["HARNESS_FAILED"], "w").close()
    sys.exit(42)
os.execv(os.environ["REAL_TMUX"], [os.environ["REAL_TMUX"], *args])
''')
                wrapper.chmod(0o755)
                log = tmp / "servers.jsonl"
                env = {**os.environ, "PATH": f"{tmp}:{os.environ['PATH']}", "REAL_TMUX": TMUX,
                       "HARNESS_LOG": str(log), "HARNESS_TARGET": target, "HARNESS_FAILED": str(tmp / "failed")}
                result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=40)
                starts = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
                try:
                    self.assertTrue((tmp / "failed").exists(), result.stdout + result.stderr)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertTrue(starts, "harness did not start a server")
                    for socket, args, pid in starts:
                        self.assertIn("-f", args)
                        self.assertEqual(args[args.index("-f") + 1], "/dev/null")
                        probe = subprocess.run([TMUX, *socket, "has-session"], capture_output=True)
                        self.assertNotEqual(probe.returncode, 0, f"server still running: {socket}")
                        self.assertTrue(pid, f"server pid unavailable: {socket}")
                        stat = Path(f"/proc/{pid}/stat")
                        self.assertTrue(not stat.exists() or stat.read_text().split()[2] == "Z", f"server process {pid} still running")
                finally:
                    for socket, _, _ in starts:
                        subprocess.run([TMUX, *socket, "kill-server"], capture_output=True)


if __name__ == "__main__":
    unittest.main()
