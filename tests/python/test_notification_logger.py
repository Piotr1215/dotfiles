#!/usr/bin/env python3
"""Behavior tests for the dbus-monitor parser behind the notification log."""

import importlib.util
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


if __name__ == "__main__":
    unittest.main()
