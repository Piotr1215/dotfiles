#!/usr/bin/env python3
"""Refresh the work margin, keeping terminal redraws independent of collection."""

import ctypes
import locale
import os
import re
import selectors
import signal
import subprocess
import sys
import termios
import time
import tty

SGR = re.compile(r"\x1b\[[0-9;]*m")
KEY = re.compile(rb"\x1b\[(?:<[0-9;]+[Mm]|[0-9;]*[A-Za-z~])")
locale.setlocale(locale.LC_CTYPE, "")
LIBC = ctypes.CDLL(None)
LIBC.wcwidth.argtypes = [ctypes.c_wchar]
LIBC.wcwidth.restype = ctypes.c_int


def physical_lines(text, width):
    """Clip each logical line to the pane width without losing its left edge."""
    rows = []
    for line in text.splitlines():
        current, used = "", 0
        for token in re.split(r"(\x1b\[[0-9;]*m)", line):
            if SGR.fullmatch(token):
                current += token
                continue
            for char in token:
                cells = max(0, LIBC.wcwidth(char))
                if used + cells > width:
                    break
                current += char
                used += cells
            else:
                continue
            break
        rows.append((current, False))
    return rows


def bottom_offset(lines, width, height):
    """Find the first logical line of the last visible page."""
    return max(0, len(lines) - height)


def paint(lines, offset, width, height):
    """Write one complete frame; never scroll the first rows out of the pane."""
    visible = lines[offset:offset + max(1, height - 1)]
    footer = f"{offset + 1 if lines else 0}-{offset + len(visible)}/{len(lines)}  j/k scroll"
    footer = footer[:max(0, width - 1)]
    frame = "".join(f"\x1b[{row};1H\x1b[0m{line}" for row, (line, _) in enumerate(visible, 1))
    footer_frame = f"\x1b[{height};1H{footer}\x1b[J" if height > 1 else ""
    sys.stdout.write(f"\x1b[?2026h\x1b[H\x1b[2J{frame}\x1b[0m{footer_frame}\x1b[?2026l")
    sys.stdout.flush()


def scroll(key, offset, lines, width, height):
    """Handle the usual scroll keys and SGR mouse-wheel reports."""
    page = max(1, height - 2)
    end = bottom_offset(lines, width, max(1, height - 1))
    if key in (b"g", b"\x1b[H", b"\x1b[1~"):
        return 0
    if key in (b"G", b"\x1b[F", b"\x1b[4~"):
        return end
    if key in (b"k", b"\x1b[A") or key.startswith(b"\x1b[<64;"):
        return max(0, offset - 1)
    if key in (b"j", b"\x1b[B") or key.startswith(b"\x1b[<65;"):
        return min(end, offset + 1)
    if key in (b"\x1b[5~", b"\x02"):
        return max(0, offset - page)
    if key in (b"\x1b[6~", b"\x06", b" "):
        return min(end, offset + page)
    return offset


def main():
    """Run a small refresh loop with a nonblocking renderer and instant resize."""
    command = sys.argv[1:]
    if not command:
        raise SystemExit("usage: __tmux_reading_margin_view.py renderer [arguments ...]")
    selector = selectors.DefaultSelector()
    selector.register(sys.stdin, selectors.EVENT_READ, "key")
    saved = termios.tcgetattr(sys.stdin)
    tty.setcbreak(sys.stdin)
    running, dirty = True, True

    def stop(_signum, _frame):
        nonlocal running
        running = False

    def resize(_signum, _frame):
        nonlocal dirty
        dirty = True

    for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(signum, stop)
    signal.signal(signal.SIGWINCH, resize)
    raw, lines, offset, size = "", [], 0, None
    process, output, next_read, pending = None, bytearray(), 0.0, b""
    sys.stdout.write("\x1b[?1049h\x1b[?7l\x1b[?25l\x1b[?1000h\x1b[?1006h")
    sys.stdout.flush()
    try:
        while running:
            current_size = os.get_terminal_size(sys.stdout.fileno())
            if current_size != size:
                size, dirty = current_size, True
            width, height = max(1, size.columns), max(1, size.lines)
            if process is None and time.monotonic() >= next_read:
                process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
                os.set_blocking(process.stdout.fileno(), False)
                selector.register(process.stdout, selectors.EVENT_READ, "board")
                output = bytearray()
                next_read = time.monotonic() + 0.2
            for event, _ in selector.select(0.03):
                if event.data == "board":
                    chunk = os.read(event.fileobj.fileno(), 65536)
                    if chunk:
                        output.extend(chunk)
                    else:
                        selector.unregister(event.fileobj)
                        event.fileobj.close()
                else:
                    data = os.read(sys.stdin.fileno(), 4096)
                    if not data:
                        running = False
                    pending += data
                    while pending:
                        if pending.startswith(b"\x1b["):
                            match = KEY.match(pending)
                            if not match:
                                break
                            key = match.group()
                        elif pending == b"\x1b":
                            break
                        else:
                            key = pending[:1]
                        pending = pending[len(key):]
                        if key == b"q":
                            running = False
                        offset = scroll(key, offset, lines, width, height)
                        dirty = True
            if process is not None and process.poll() is not None and process.stdout.closed:
                incoming = output.decode(errors="replace") if process.returncode == 0 else "Roster read failed\n"
                dirty = dirty or incoming != raw
                raw, process = incoming, None
            if dirty and raw:
                lines = physical_lines(raw, width)
                offset = min(offset, bottom_offset(lines, width, max(1, height - 1)))
                paint(lines, offset, width, height)
                dirty = False
    finally:
        try:
            if process is not None and process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                process.wait()
        finally:
            selector.close()
            termios.tcsetattr(sys.stdin, termios.TCSANOW, saved)
            sys.stdout.write("\x1b[?1000l\x1b[?1006l\x1b[?7h\x1b[?25h\x1b[?1049l")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
