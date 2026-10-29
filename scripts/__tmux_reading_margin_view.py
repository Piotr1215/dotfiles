#!/usr/bin/env python3
"""Refresh the work margin, keeping terminal redraws independent of collection."""

import ctypes
import fcntl
import hashlib
import locale
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import termios
import tty

SGR = re.compile(r"\x1b\[[0-9;]*m")
KEY = re.compile(rb"\x1b\[(?:<[0-9;]+[Mm]|[0-9;]*[A-Za-z~])")
locale.setlocale(locale.LC_CTYPE, "")
LIBC = ctypes.CDLL(None)
LIBC.wcwidth.argtypes = [ctypes.c_wchar]
LIBC.wcwidth.restype = ctypes.c_int


def shared_state_dir():
    override = os.environ.get("TMUX_READING_MARGIN_STATE_DIR")
    if override:
        return Path(override)
    root = os.environ.get("XDG_RUNTIME_DIR") or os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    socket = os.environ.get("TMUX", "").split(",", 1)[0]
    return Path(root) / "reading-margin-shared" / hashlib.sha256(socket.encode()).hexdigest()


def atomic_write(path, data):
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    tmp.write_text(data)
    os.replace(tmp, path)


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


def jump_targets(text):
    """Map each nonblank agent block row to its full SESSION token."""
    rows = [SGR.sub("", line) for line in text.splitlines()]
    targets = [None] * len(rows)
    start = None
    for index in range(len(rows) + 1):
        line = rows[index] if index < len(rows) else ""
        if start is not None and (not line.strip() or re.match(r"^\s*AGENT:\s", line)):
            for item in rows[start:index]:
                match = re.match(r"^\s*SESSION:\s*(jump:[^\s]+)", item)
                if match:
                    targets[start:index] = [match.group(1)] * (index - start)
                    break
            start = None
        if re.match(r"^\s*AGENT:\s", line):
            start = index
    return targets


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
        return min(max(end, offset), offset + 1)
    if key in (b"\x1b[5~", b"\x02"):
        return max(0, offset - page)
    if key in (b"\x1b[6~", b"\x06", b" "):
        return min(max(end, offset), offset + page)
    return offset


def main():
    """Run a small refresh loop with a nonblocking renderer and instant resize."""
    command = sys.argv[1:]
    if command == ["--state-dir"]:
        print(shared_state_dir())
        return
    if not command:
        raise SystemExit("usage: __tmux_reading_margin_view.py renderer [arguments ...]")
    jump_command = os.environ.get("TMUX_READING_MARGIN_JUMP_COMMAND", str(Path(__file__).with_name("__tmux_jump.sh")))
    state = shared_state_dir()
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    leader_fd = os.open(state / "leader.lock", os.O_CREAT | os.O_RDWR, 0o600)
    scroll_fd = os.open(state / "scroll.lock", os.O_CREAT | os.O_RDWR, 0o600)
    leader = False
    frame_version, offset_version = None, None
    collector, parent_pipe = None, None
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
    targets, jump_children = [], []
    painted_targets, painted_offset, painted_size = [], 0, (0, 0)
    pending = b""
    sys.stdout.write("\x1b[?1049h\x1b[?7l\x1b[?25l\x1b[?1000h\x1b[?1006h")
    sys.stdout.flush()
    try:
        while running:
            jump_children = [child for child in jump_children if child.poll() is None]
            current_size = os.get_terminal_size(sys.stdout.fileno())
            if current_size != size:
                size, dirty = current_size, True
            width, height = max(1, size.columns), max(1, size.lines)
            if collector is not None and collector.poll() is not None:
                os.close(parent_pipe)
                parent_pipe = None
                collector = None
                os.close(leader_fd)
                leader_fd = os.open(state / "leader.lock", os.O_CREAT | os.O_RDWR, 0o600)
                leader = False
            if not leader:
                try:
                    fcntl.flock(leader_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    read_fd, parent_pipe = os.pipe()
                    env = dict(os.environ, MARGIN_LEADER_FD=str(leader_fd), MARGIN_PARENT_FD=str(read_fd))
                    collector_command = os.environ.get("TMUX_READING_MARGIN_COLLECT_COMMAND", str(Path(__file__).with_name("__tmux_reading_margin_collect")))
                    try:
                        collector = subprocess.Popen([collector_command, "--state-dir", str(state), "--", *command], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env, pass_fds=(leader_fd, read_fd))
                    except OSError:
                        os.close(parent_pipe)
                        parent_pipe = None
                        fcntl.flock(leader_fd, fcntl.LOCK_UN)
                        raise
                    finally:
                        os.close(read_fd)
                    leader = True
                except BlockingIOError:
                    pass
            for filename in ("frame", "offset"):
                path = state / filename
                try:
                    version = path.stat().st_mtime_ns
                    if filename == "frame" and version != frame_version:
                        raw = path.read_text()
                        targets = jump_targets(raw)
                        frame_version, dirty = version, True
                    elif filename == "offset" and version != offset_version:
                        offset = max(0, int(path.read_text()))
                        offset_version, dirty = version, True
                except (OSError, ValueError):
                    pass
            for event, _ in selector.select(0.1):
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
                    click = re.fullmatch(rb"\x1b\[<0;([0-9]+);([0-9]+)M", key)
                    if click:
                        x, y = map(int, click.groups())
                        row = painted_offset + y - 1
                        painted_width, painted_height = painted_size
                        if 1 <= x <= painted_width and 1 <= y <= max(1, painted_height - 1) and row < len(painted_targets) and painted_targets[row]:
                            try:
                                jump_children.append(subprocess.Popen([jump_command, painted_targets[row]], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True))
                            except OSError:
                                pass
                    fcntl.flock(scroll_fd, fcntl.LOCK_EX)
                    try:
                        try:
                            current_offset = max(0, int((state / "offset").read_text()))
                        except (OSError, ValueError):
                            current_offset = 0
                        updated = scroll(key, current_offset, lines, width, height)
                        if updated != current_offset:
                            atomic_write(state / "offset", str(updated))
                        offset = updated
                    finally:
                        fcntl.flock(scroll_fd, fcntl.LOCK_UN)
                    dirty = True
            if dirty and raw:
                lines = physical_lines(raw, width)
                offset = min(offset, max(0, len(lines) - 1))
                paint(lines, offset, width, height)
                painted_targets, painted_offset, painted_size = targets, offset, (width, height)
                dirty = False
    finally:
        try:
            if parent_pipe is not None:
                os.close(parent_pipe)
            if collector is not None:
                collector.wait()
        finally:
            selector.close()
            os.close(leader_fd)
            os.close(scroll_fd)
            termios.tcsetattr(sys.stdin, termios.TCSANOW, saved)
            sys.stdout.write("\x1b[?1000l\x1b[?1006l\x1b[?7h\x1b[?25h\x1b[?1049l")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
