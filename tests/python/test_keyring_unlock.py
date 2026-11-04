"""Exercise __keyring_unlock.py against a fake session bus; no real keyring is touched.

Runs under the system python3 (it needs PyGObject): python3 -m unittest tests/python/test_keyring_unlock.py
"""
import importlib.util
from pathlib import Path
import unittest
from unittest import mock

from gi.repository import GLib

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("keyring_unlock", ROOT / "scripts/__keyring_unlock.py")
unlock = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(unlock)


class FakeBus:
    """Answers the four calls the script makes; records each method name."""

    def __init__(self, locked_states, accept=True):
        self.locked_states = list(locked_states)
        self.accept = accept
        self.calls = []

    def call_sync(self, _bus, path, _iface, method, params, *_rest):
        self.calls.append(method)
        if method == "Get":
            return GLib.Variant("(v)", (GLib.Variant("b", self.locked_states.pop(0)),))
        if method == "OpenSession":
            return GLib.Variant("(vo)", (GLib.Variant("s", ""), "/org/freedesktop/secrets/session/s1"))
        if method == "UnlockWithMasterPassword":
            self.unlock_args = params.unpack()
            if not self.accept:
                raise GLib.Error("The password was invalid")
            return None
        if method == "Close":
            return None
        raise AssertionError(f"unexpected call {method} on {path}")


class KeyringUnlockTests(unittest.TestCase):
    def run_main(self, bus, name="login", password="pw"):
        with mock.patch.object(unlock.Gio, "bus_get_sync", return_value=bus), \
             mock.patch.object(unlock.getpass, "getpass", return_value=password) as asked, \
             mock.patch.object(unlock.sys, "argv", ["__keyring_unlock.py", name]):
            return unlock.main(), asked

    def test_collection_names_are_escaped_like_dbus_object_paths(self):
        self.assertEqual(unlock.collection_path("login"), "/org/freedesktop/secrets/collection/login")
        # 4 Nov 2026: Default_keyring lives at .../Default_5fkeyring on serval.
        self.assertEqual(unlock.collection_path("Default_keyring"),
                         "/org/freedesktop/secrets/collection/Default_5fkeyring")
        self.assertEqual(unlock.collection_path("/org/x"), "/org/x")

    def test_unlocked_collection_never_asks_for_a_password(self):
        bus = FakeBus([False])
        status, asked = self.run_main(bus)
        self.assertEqual(status, 0)
        asked.assert_not_called()
        self.assertEqual(bus.calls, ["Get"])

    def test_correct_password_unlocks_through_master_password_and_closes_session(self):
        bus = FakeBus([True, False, False])
        status, _ = self.run_main(bus, "Default_keyring", "secret")
        self.assertEqual(status, 0)
        path, (session, params, value, content_type) = bus.unlock_args
        self.assertEqual(path, "/org/freedesktop/secrets/collection/Default_5fkeyring")
        self.assertEqual((session, bytes(value), content_type),
                         ("/org/freedesktop/secrets/session/s1", b"secret", "text/plain"))
        self.assertEqual(bus.calls, ["Get", "OpenSession", "UnlockWithMasterPassword", "Close", "Get", "Get"])

    def test_refused_password_returns_1_and_still_closes_session(self):
        bus = FakeBus([True], accept=False)
        status, _ = self.run_main(bus)
        self.assertEqual(status, 1)
        self.assertEqual(bus.calls[-1], "Close")


if __name__ == "__main__":
    unittest.main()
