#!/usr/bin/env python3
"""Behavior tests for the dbus-monitor parser and the trim of the notification log."""

import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[2] / "scripts" / "__notification_logger.py"


def load_module():
    spec = importlib.util.spec_from_file_location("notification_logger", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def frame(app, summary, body):
    """One Notify method call exactly as dbus-monitor prints it."""
    return (
        "method call time=1788115646.922482 sender=:1.1932 -> destination=:1.49 "
        "serial=9 path=/org/freedesktop/Notifications; "
        "interface=org.freedesktop.Notifications; member=Notify\n"
        f'   string "{app}"\n'
        "   uint32 0\n"
        '   string ""\n'
        f'   string "{summary}"\n'
        f'   string "{body}"\n'
        "   array [\n"
        "   ]\n"
        "   array [\n"
        "      dict entry(\n"
        '         string "urgency"\n'
        "         variant             byte 0\n"
        "      )\n"
        "   ]\n"
        "   int32 -1\n"
    )


class ParseTest(unittest.TestCase):
    def setUp(self):
        self.parse = load_module().parse

    def records(self, text):
        return list(self.parse(text.splitlines(keepends=True)))

    def test_single_line_body(self):
        got = self.records(frame("notify-send", "Backup Complete", "finished"))
        self.assertEqual(got, [("notify-send", "Backup Complete", "finished")])

    def test_multiline_body_is_kept_whole(self):
        """Commit Memory and friends put a newline in the body, and dbus-monitor
        prints it literally. Those notifications used to vanish from the log."""
        body = 'memories: 29addd3\nFailed after 8 attempts: {"status":"retry"}'
        got = self.records(frame("notify-send", "Commit Memory", body))
        self.assertEqual(got, [("notify-send", "Commit Memory", body)])

    def test_body_with_quotes_survives(self):
        body = '{"status":"retry","reason":"commit is no longer available"}'
        got = self.records(frame("notify-send", "Commit Memory", body))
        self.assertEqual(got, [("notify-send", "Commit Memory", body)])

    def test_empty_body(self):
        got = self.records(frame("flameshot", "Flameshot Info", ""))
        self.assertEqual(got, [("flameshot", "Flameshot Info", "")])

    def test_notify_without_body_field_is_dropped(self):
        text = (
            "method call time=1 sender=:1.1 -> destination=:1.2 serial=9 "
            "path=/org/freedesktop/Notifications; "
            "interface=org.freedesktop.Notifications; member=Notify\n"
            '   string "app"\n'
            "   uint32 0\n"
            '   string ""\n'
            "   array [\n"
            "   ]\n"
        )
        self.assertEqual(self.records(text), [])

    def test_multiline_body_does_not_swallow_the_next_notification(self):
        text = (
            frame("notify-send", "First", "one\ntwo")
            + frame("flameshot", "Second", "saved")
        )
        self.assertEqual(self.records(text), [
            ("notify-send", "First", "one\ntwo"),
            ("flameshot", "Second", "saved"),
        ])

    def test_dbus_double_delivery_yields_two_records(self):
        """The parser reports both frames; main() dedups them by time window."""
        text = frame("a", "s", "b") * 2
        self.assertEqual(len(self.records(text)), 2)


# Appends "w<k> seq:<i>" lines the way producers do: open, append, close.
WRITER = """
import sys, time
path, k, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
for i in range(n):
    with open(path, "a") as f:
        f.write(f"w{k} seq:{i}\\n")
    time.sleep(0.002)
"""


class TrimTest(unittest.TestCase):
    def setUp(self):
        self.logger = load_module()
        self.dir = tempfile.TemporaryDirectory()
        self.logger.LOG = os.path.join(self.dir.name, "notifications.log")

    def tearDown(self):
        self.dir.cleanup()

    def lines(self):
        with open(self.logger.LOG) as f:
            return f.read().splitlines()

    def test_keeps_the_most_recent_lines(self):
        with open(self.logger.LOG, "w") as f:
            f.writelines(f"line {i}\n" for i in range(50))
        self.logger.MAX_BYTES, self.logger.KEEP_LINES = 100, 10
        self.logger.trim_if_big()
        self.assertEqual(self.lines(), [f"line {i}" for i in range(40, 50)])

    def test_leaves_a_small_log_alone(self):
        with open(self.logger.LOG, "w") as f:
            f.write("one\n")
        self.logger.MAX_BYTES = 100
        self.logger.trim_if_big()
        self.assertEqual(self.lines(), ["one"])

    def test_concurrent_appends_survive_a_trim(self):
        # KEEP_LINES above the line count makes every trim keep everything,
        # so any line missing at the end was lost to the race, not trimmed.
        open(self.logger.LOG, "w").close()
        self.logger.MAX_BYTES, self.logger.KEEP_LINES = 1, 10**6
        writers, n = 4, 400
        procs = [subprocess.Popen([sys.executable, "-c", WRITER, self.logger.LOG, str(k), str(n)])
                 for k in range(writers)]
        trims = 0
        while any(p.poll() is None for p in procs):
            self.logger.trim_if_big()
            trims += 1
        self.logger.trim_if_big()
        self.assertGreater(trims, 2)
        got = self.lines()
        torn = [x for x in got if not re.fullmatch(r"w\d seq:\d+", x)]
        self.assertEqual(torn, [])
        want = sorted(f"w{k} seq:{i}" for k in range(writers) for i in range(n))
        self.assertEqual(len(set(want) - set(got)), 0, "lines lost to a trim")
        self.assertEqual(sorted(got), want)


if __name__ == "__main__":
    unittest.main()
