#!/usr/bin/env python3
"""Native messaging host: lets the tab-detach chrome extension apply a layout.

Chrome extensions cannot run local commands, so detaching a tab and tiling the
result could previously only be joined by synthesising keystrokes back at the
browser. That raced the window creation and fought the modifiers of whatever
chord triggered it. The extension now calls straight through, after the window
it created already exists, so there is nothing to wait for and nothing to guess.
"""
import json
import struct
import subprocess
import sys

LAYOUTS = "/home/decoder/dev/dotfiles/scripts/__layouts.sh"
# Whitelist, not passthrough: anything that can reach this host would otherwise
# choose the argument. 3 is browser+browser, 5 is max browser.
ALLOWED = {"3", "5"}


def read_message():
    header = sys.stdin.buffer.read(4)
    if len(header) < 4:
        return None
    length = struct.unpack("<I", header)[0]
    return json.loads(sys.stdin.buffer.read(length).decode("utf-8"))


def write_message(obj):
    data = json.dumps(obj).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(data)))
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def main():
    message = read_message()
    if message is None:  # not "not message": {} is falsy and must still answer
        return
    layout = str(message.get("layout", ""))
    if layout not in ALLOWED:
        write_message({"ok": False, "error": "layout not allowed: " + layout})
        return
    result = subprocess.run([LAYOUTS, layout], capture_output=True, text=True)
    write_message({"ok": result.returncode == 0, "stderr": result.stderr[-500:]})


if __name__ == "__main__":
    main()
