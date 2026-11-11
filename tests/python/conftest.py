"""Keep browser launchers and the signed-in Chrome bridge out of tests."""
import os

import pytest


@pytest.fixture(autouse=True)
def guard_browser_launches(tmp_path, monkeypatch):
    guard = tmp_path / "browser-guard"
    guard.mkdir()
    attempts = guard / "attempts"
    launcher = guard / "blocked-browser"
    launcher.write_text(
        '#!/bin/sh\nprintf "%s\\n" "$0 $*" >> "$BROWSER_TEST_ATTEMPTS"\n'
        'echo "browser launch blocked by test guard" >&2\nexit 97\n'
    )
    launcher.chmod(0o755)
    for name in ("xdg-open", "google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "firefox"):
        (guard / name).symlink_to(launcher)
    monkeypatch.setenv("BROWSER_TEST_ATTEMPTS", str(attempts))
    monkeypatch.setenv("PATH", str(guard) + os.pathsep + os.environ.get("PATH", ""))
    monkeypatch.setenv("BROWSER", str(launcher))
    monkeypatch.setenv("HANDOFF_TAB_COMMAND", str(launcher))
    monkeypatch.setenv("AGENT_BROWSER_NATIVE_SOCKET", str(guard / "no-browser.sock"))
    yield
    if attempts.exists():
        pytest.fail("browser launch attempted during test:\n" + attempts.read_text())
