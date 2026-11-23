#!/usr/bin/env python3
"""Refresh the work margin, keeping terminal redraws independent of collection."""

import ctypes
import fcntl
import hashlib
import json
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


def decode_frame(data):
    """Read text and its matching pane order from one atomic publication."""
    try:
        frame = json.loads(data)
        if (isinstance(frame, dict) and isinstance(frame.get("text"), str) and
                isinstance(frame.get("panes"), list) and
                all(isinstance(pane, str) and re.fullmatch(r"%[0-9]+", pane) for pane in frame["panes"])):
            return frame["text"], frame["panes"]
    except ValueError:
        pass
    return data, []


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


def mark_active_agent(text, active_pane, pane_order):
    """Mark one live block by pane ID without changing the shared frame."""
    rows = text.splitlines(keepends=True)
    targets = jump_targets(text)
    headers = [i for i, row in enumerate(rows)
               if targets[i] and re.match(r"^\s*AGENT:\s", SGR.sub("", row))]
    if not active_pane or len(headers) != len(pane_order) or active_pane not in pane_order:
        return text
    index = headers[pane_order.index(active_pane)]
    rows[index] = re.sub(r"(AGENT:(?:[ \t]|\x1b\[[0-9;]*m)*)", r"\1* ", rows[index], count=1)
    return "".join(rows)


def child_statuses(rows):
    """Count child STATUS words, each in the colour of its first appearance."""
    counts, colours = {}, {}
    for row in rows:
        if "STATUS:" not in SGR.sub("", row):
            continue
        colour = ""
        for token in re.split(r"(\x1b\[[0-9;]*m)", row.split("STATUS:", 1)[1]):
            if SGR.fullmatch(token):
                colour = "" if token == "\x1b[0m" else token
            elif token.strip():
                word = token.split(":")[0].split()[0]
                counts[word] = counts.get(word, 0) + 1
                colours.setdefault(word, colour)
                break
    return ", ".join(f"{colours[word]}{count} {word}\x1b[0m"
                     for word, count in sorted(counts.items(), key=lambda item: -item[1]))


def fold_subagents(text, expanded):
    """Hide each parent's indented agent blocks behind one toggle row.

    Returns the shown text and, per shown row, the parent key its toggle row
    flips (None elsewhere). Collapsed is the default: a key is open only while
    it is in expanded. A hidden active agent lends its marker to the toggle row.
    """
    rows = text.splitlines()
    plain = [SGR.sub("", row) for row in rows]
    targets = jump_targets(text)
    shown, folds, parent, index = [], [], "", 0
    while index < len(rows):
        if not re.match(r"^\s+AGENT:\s", plain[index]):
            if plain[index][:1].strip():
                parent = targets[index] or plain[index].strip()
            shown.append(rows[index])
            folds.append(None)
            index += 1
            continue
        end = index
        while end < len(rows) and not plain[end][:1].strip():
            end += 1
        while not plain[end - 1].strip():
            end -= 1
        run = rows[index:end]
        count = sum(1 for line in plain[index:end] if re.match(r"^\s+AGENT:\s", line))
        is_open = parent in expanded
        marker = "* " if not is_open and any(
            re.match(r"^\s+AGENT:\s+\* ", line) for line in plain[index:end]) else ""
        indent = re.match(r"^\s*", plain[index]).group()
        noun = "subagent" if count == 1 else "subagents"
        statuses = child_statuses(run)
        shown.append(f"{indent}\x1b[90m{'▾' if is_open else '▸'} {marker}{count} {noun}"
                     + (f":\x1b[0m {statuses}" if statuses else "\x1b[0m"))
        folds.append(parent)
        if is_open:
            shown.extend(["", *run])
            folds.extend([None] * (len(run) + 1))
        index = end
    return "\n".join(shown) + ("\n" if text.endswith("\n") else ""), folds


def read_expanded(path):
    """Read the shared set of open parent keys; anything unreadable is all closed."""
    try:
        keys = json.loads(path.read_text())
    except (OSError, ValueError):
        return set()
    return {key for key in keys if isinstance(key, str)} if isinstance(keys, list) else set()


def toggled(expanded, keys):
    """Open every key when any is closed, else close them all."""
    return expanded | keys if keys - expanded else expanded - keys


def bottom_offset(lines, width, height):
    """Find the first logical line of the last visible page."""
    return max(0, len(lines) - height)


def paint(lines, offset, width, height):
    """Write one complete frame; never scroll the first rows out of the pane."""
    visible = lines[offset:offset + max(1, height)]
    frame = "".join(f"\x1b[{row};1H\x1b[0m{line}" for row, (line, _) in enumerate(visible, 1))
    sys.stdout.write(f"\x1b[?2026h\x1b[H\x1b[2J{frame}\x1b[0m\x1b[?2026l")
    sys.stdout.flush()


def scroll(key, offset, lines, width, height):
    """Handle the usual scroll keys and SGR mouse-wheel reports."""
    page = max(1, height - 1)
    end = bottom_offset(lines, width, max(1, height))
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
    window = os.environ.get("TMUX_READING_MARGIN_WINDOW", "")
    active_file = state / f"active-{window}"
    active_pane, active_version = "", None
    if re.fullmatch(r"@[0-9]+", window):
        # One query on startup; pane changes arrive through the async tmux hook.
        try:
            active_version = active_file.stat().st_mtime_ns if active_file.exists() else None
            active_pane = subprocess.check_output(
                ["tmux", "display-message", "-p", "-t", window, "#{pane_id}"],
                text=True, timeout=1).strip()
        except (OSError, subprocess.SubprocessError):
            pass
    leader_fd = os.open(state / "leader.lock", os.O_CREAT | os.O_RDWR, 0o600)
    scroll_fd = os.open(state / "scroll.lock", os.O_CREAT | os.O_RDWR, 0o600)
    leader = False
    frame_version, offset_version, expanded_version = None, None, None
    expanded = set()
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
    pane_order = []
    targets, folds, jump_children = [], [], []
    painted_targets, painted_folds, painted_offset, painted_size = [], [], 0, (0, 0)
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
            for filename in ("frame", "offset", "expanded"):
                path = state / filename
                try:
                    version = path.stat().st_mtime_ns
                    if filename == "frame" and version != frame_version:
                        raw, pane_order = decode_frame(path.read_text())
                        frame_version, dirty = version, True
                    elif filename == "offset" and version != offset_version:
                        offset = max(0, int(path.read_text()))
                        offset_version, dirty = version, True
                    elif filename == "expanded" and version != expanded_version:
                        expanded = read_expanded(path)
                        expanded_version, dirty = version, True
                except (OSError, ValueError):
                    pass
            if window:
                try:
                    version = active_file.stat().st_mtime_ns
                    if version != active_version:
                        pane = active_file.read_text().strip()
                        if re.fullmatch(r"%[0-9]+", pane):
                            active_pane, active_version, dirty = pane, version, True
                except OSError:
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
                    flip = set()
                    if key == b"s":
                        flip = {fold for fold in painted_folds if fold is not None}
                    click = re.fullmatch(rb"\x1b\[<0;([0-9]+);([0-9]+)M", key)
                    if click:
                        x, y = map(int, click.groups())
                        row = painted_offset + y - 1
                        painted_width, painted_height = painted_size
                        inside = 1 <= x <= painted_width and 1 <= y <= painted_height
                        if inside and row < len(painted_folds) and painted_folds[row] is not None:
                            flip = {painted_folds[row]}
                        elif inside and row < len(painted_targets) and painted_targets[row]:
                            try:
                                jump_children.append(subprocess.Popen([jump_command, painted_targets[row]], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True))
                            except OSError:
                                pass
                    fcntl.flock(scroll_fd, fcntl.LOCK_EX)
                    try:
                        if flip:
                            # Fold state is shared like the offset, so every
                            # margin shows the same rows at the same position.
                            expanded = toggled(read_expanded(state / "expanded"), flip)
                            atomic_write(state / "expanded", json.dumps(sorted(expanded)))
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
                # Mark before folding: the marker matches headers to the full
                # pane order, and a hidden active agent marks its toggle row.
                shown, folds = fold_subagents(mark_active_agent(raw, active_pane, pane_order), expanded)
                targets = jump_targets(shown)
                lines = physical_lines(shown, width)
                offset = min(offset, max(0, len(lines) - 1))
                paint(lines, offset, width, height)
                painted_targets, painted_folds, painted_offset, painted_size = targets, folds, offset, (width, height)
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
