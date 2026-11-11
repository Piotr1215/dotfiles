"""Tests for scripts/__reminder_gui.py, the GTK dialogs behind __reminder.sh.

The pure helpers and the Dracula CSS run anywhere GTK 3 imports. The window
tests start one Xvfb for the module and drive the real dialog with xdotool;
they skip when Xvfb or xdotool is missing. The module skips under a Python
without PyGObject (the uv pytest tool); run it with the system Python:

    uv venv --system-site-packages --python /usr/bin/python3 /tmp/gi-venv
    uv pip install --python /tmp/gi-venv pytest
    /tmp/gi-venv/bin/pytest tests/python/test_reminder_gui.py
"""

import importlib.util
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

import pytest

pytest.importorskip("gi")

GUI =Path(__file__).resolve().parents[2] / "scripts/__reminder_gui.py"
SPEC = importlib.util.spec_from_file_location("reminder_gui", GUI)
gui = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gui)

DEADLINE = {
    "kind": "deadline",
    "title": "mail: Tailscale renewal (Kelsea)",
    "body": "The deadline passed.\nChecks: 594 run(s), last rc=0.",
    "due": "Wed 11 Nov 09:00",
    "repeat": "every 30m",
    "subject_type": "task",
    "pick": "2026-11-12 09:00",
}


def test_dracula_css_parses_under_gtk3():
    # A parse error drops the whole theme silently at runtime.
    gui.Gtk.CssProvider().load_from_data(gui.DRACULA_CSS)


def test_fit_size_caps_at_the_work_area_and_keeps_natural_height():
    assert gui.fit_size(3840, 2160, gui.SIZES["alert"]) == (1100, 820)
    assert gui.fit_size(1366, 728, gui.SIZES["alert"]) == (1100, 655)
    assert gui.fit_size(1920, 1080, gui.SIZES["confirm"]) == (520, -1)


def test_alert_meta_names_deadline_or_due():
    assert gui.alert_meta(DEADLINE, True) == "Deadline Wed 11 Nov 09:00 · checks every 30m"
    show = {"due": "Tue 08 Sep 09:00", "late": "2h 5m"}
    assert gui.alert_meta(show, False) == "Due Tue 08 Sep 09:00 · 2h 5m late"
    assert gui.alert_meta({}, False) == ""


def test_instruction_status_says_what_send_to_ai_carries():
    assert gui.instruction_status("  \n") == "No instruction: Send to AI hands over the report alone"
    assert gui.instruction_status("renew it\nthen close") == (
        "Instruction: 2 lines, 19 chars, goes with Send to AI"
    )


# --- the real windows under Xvfb ------------------------------------------


@pytest.fixture(scope="module")
def display():
    if not shutil.which("Xvfb") or not shutil.which("xdotool"):
        pytest.skip("Xvfb or xdotool missing")
    read_fd, write_fd = os.pipe()
    xvfb = subprocess.Popen(
        ["Xvfb", "-displayfd", str(write_fd), "-screen", "0", "1920x1080x24", "-nolisten", "tcp"],
        pass_fds=(write_fd,),
        stderr=subprocess.DEVNULL,
    )
    os.close(write_fd)
    with os.fdopen(read_fd) as pipe:
        number = pipe.readline().strip()
    if not number:
        xvfb.kill()
        pytest.skip("Xvfb did not report a display")
    yield f":{number}"
    xvfb.terminate()
    xvfb.wait(timeout=5)


def drive(display, mode, request, *steps):
    """Open the dialog, focus it, run xdotool steps ("type:TEXT" or
    "key:SPEC"), and return (exit code, stdout, (width, height))."""
    env = dict(os.environ, DISPLAY=display)
    proc = subprocess.Popen(
        ["python3", str(GUI), mode],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env=env,
        text=True,
    )
    proc.stdin.write(json.dumps(request))
    proc.stdin.close()
    xdo = lambda *args: subprocess.run(  # noqa: E731
        ["xdotool", *args], env=env, capture_output=True, text=True
    ).stdout.strip()
    wid = ""
    for _ in range(80):
        wid = xdo("search", "--pid", str(proc.pid), "--onlyvisible").split("\n")[0]
        if wid:
            break
        time.sleep(0.1)
    if not wid:
        proc.kill()
        pytest.fail("dialog window never appeared")
    time.sleep(0.4)
    geometry = dict(
        line.split("=", 1) for line in xdo("getwindowgeometry", "--shell", wid).splitlines()
    )
    xdo("windowfocus", wid)
    time.sleep(0.2)
    for step in steps:
        kind, _, arg = step.partition(":")
        if kind == "type":
            xdo("type", "--delay", "5", arg)
        else:
            xdo("key", arg)
        time.sleep(0.15)
    try:
        out = proc.stdout.read()
        code = proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        pytest.fail("dialog still open after the steps")
    return code, out.strip(), (int(geometry["WIDTH"]), int(geometry["HEIGHT"]))


def test_alert_opens_big_and_sends_the_typed_instruction(display):
    code, out, size = drive(
        display, "alert", DEADLINE,
        "type:renew on the annual plan", "key:Return", "type:then close the thread",
        "key:ctrl+Return",
    )
    assert code == 0
    assert size == (1100, 820)
    assert json.loads(out) == {
        "action": "ai",
        "note": "renew on the annual plan\nthen close the thread",
    }


def test_alert_send_without_instruction_carries_no_note(display):
    code, out, _ = drive(display, "alert", {**DEADLINE, "kind": "show"}, "key:ctrl+Return")
    assert (code, json.loads(out)) == (0, {"action": "ai"})


def test_alert_reopens_with_the_instruction_from_before_open(display):
    code, out, _ = drive(display, "alert", {**DEADLINE, "note": "keep this"}, "key:ctrl+Return")
    assert (code, json.loads(out)) == (0, {"action": "ai", "note": "keep this"})


def test_alert_esc_closes_for_now_without_a_choice(display):
    code, out, _ = drive(display, "alert", DEADLINE, "type:half typed", "key:Escape")
    assert (code, out) == (1, "")


def test_form_saves_on_enter_from_the_when_field(display):
    code, out, _ = drive(
        display, "form", {"title": "Add reminder"},
        "type:Stand up", "key:alt+w", "type:10m", "key:Return",
    )
    assert code == 0
    assert json.loads(out) == {"label": "Stand up", "when": "10m", "repeat": "", "subject": ""}


def test_confirm_and_error_return_their_choice(display):
    # Enter on a delete confirm cancels; confirming takes Tab to the button.
    assert drive(display, "confirm", {"message": "Delete?"}, "key:Return")[:2] == (1, "")
    assert drive(display, "confirm", {"message": "Delete?"}, "key:Tab", "key:Return")[:2] == (
        0, '{"confirmed": true}'
    )
    assert drive(display, "error", {"message": "Failed."}, "key:Return")[:2] == (
        0, '{"closed": true}'
    )
