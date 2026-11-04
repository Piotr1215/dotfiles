#!/usr/bin/env python3
"""Unlock a gnome-keyring collection without the desktop prompt.

For when the running daemon accepts Unlock but never shows its dialog. The password is read
hidden from the terminal (getpass) and sent to the daemon over a plain Secret Service session
on the local session bus, the same path seahorse uses. Usage: __keyring_unlock.py [login|Default_keyring|<object path>]
"""
import getpass
import sys
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

BUS = "org.freedesktop.secrets"
ROOT = "/org/freedesktop/secrets"

def collection_path(name):
    """Map a keyring name to its object path; D-Bus escapes other characters as _xx hex."""
    if name.startswith("/"):
        return name
    return f"{ROOT}/collection/" + "".join(c if c.isalnum() else f"_{ord(c):02x}" for c in name)


def locked(bus, path):
    value = bus.call_sync(BUS, path, "org.freedesktop.DBus.Properties", "Get",
                          GLib.Variant("(ss)", ("org.freedesktop.Secret.Collection", "Locked")),
                          GLib.VariantType("(v)"), Gio.DBusCallFlags.NONE, 5000, None)
    return value.unpack()[0]

def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "login"
    path = collection_path(name)
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    if not locked(bus, path):
        print(f"{path}: already unlocked")
        return 0
    password = getpass.getpass(f"Password for {name}: ").encode()
    _, session = bus.call_sync(BUS, ROOT, "org.freedesktop.Secret.Service", "OpenSession",
                               GLib.Variant("(sv)", ("plain", GLib.Variant("s", ""))),
                               GLib.VariantType("(vo)"), Gio.DBusCallFlags.NONE, 5000, None).unpack()
    secret = GLib.Variant("(oayays)", (session, b"", password, "text/plain"))
    try:
        bus.call_sync(BUS, ROOT, "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface",
                      "UnlockWithMasterPassword", GLib.Variant.new_tuple(GLib.Variant("o", path), secret),
                      None, Gio.DBusCallFlags.NONE, 10000, None)
    except GLib.Error as e:
        print(f"{path}: unlock refused: {e.message}", file=sys.stderr)
        return 1
    finally:
        password = None
        bus.call_sync(BUS, session, "org.freedesktop.Secret.Session", "Close", None, None,
                      Gio.DBusCallFlags.NONE, 5000, None)
    print(f"{path}: {'still locked' if locked(bus, path) else 'unlocked'}")
    return 0 if not locked(bus, path) else 1

if __name__ == "__main__":
    sys.exit(main())
