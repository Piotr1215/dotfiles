"""The test guard blocks a launcher and records its arguments."""
import os
from pathlib import Path
import subprocess


def test_browser_guard_blocks_launcher():
    result = subprocess.run(["xdg-open", "https://example.invalid/fixture"], capture_output=True, text=True)
    attempts = Path(os.environ["BROWSER_TEST_ATTEMPTS"])
    assert result.returncode == 97
    assert "browser launch blocked" in result.stderr
    assert "https://example.invalid/fixture" in attempts.read_text()
    attempts.unlink()
