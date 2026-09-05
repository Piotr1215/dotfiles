#!/usr/bin/env python3
"""Live multiline regex expansion from the focused tmux pane."""

from __future__ import annotations

import argparse
import fcntl
import json
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict, dataclass
from pathlib import Path

SCRIPT = Path(__file__).resolve()
DELIVER = SCRIPT.with_name("__lib_pane_deliver.sh")
INITIAL_QUERY = "^"
INLINE_TRIGGER = ";;^"


@dataclass(frozen=True)
class Match:
    text: str
    start_line: int
    end_line: int


def clean_scrollback(text: str) -> str:
    """Remove terminal UI margins while retaining hard line boundaries."""
    margin = re.compile(r"^\s*(?:[•›]\s+)?")
    return "\n".join(margin.sub("", line).rstrip() for line in text.splitlines())


def prose_friendly_pattern(pattern: str) -> str:
    """Let a keyboard apostrophe match either straight or smart prose."""
    out: list[str] = []
    escaped = False
    in_class = False
    for char in pattern:
        if escaped:
            out.append(char)
            escaped = False
        elif char == "\\":
            out.append(char)
            escaped = True
        elif char == "[":
            out.append(char)
            in_class = True
        elif char == "]" and in_class:
            out.append(char)
            in_class = False
        elif char == "'" and not in_class:
            out.append("['’]")
        else:
            out.append(char)
    return "".join(out)


def anchored_line_prefix(pattern: str) -> str | None:
    """Return the literal locator in a complete or unfinished ``^words$`` form."""
    if not pattern.startswith("^"):
        return None
    body = pattern[1:-1] if pattern.endswith("$") else pattern[1:]
    if not body or re.search(r"[\\.*+?()[\]{}|^$]", body):
        return None
    return body


def open_ended_line_pattern(pattern: str) -> str | None:
    """Return the start expression in the shorthand ``^start.*$`` form."""
    if not pattern.startswith("^"):
        return None
    body = pattern[1:-1] if pattern.endswith("$") else pattern[1:]
    if not body.endswith(".*") or body.endswith(r"\.*"):
        return None
    start = body[:-2]
    return start or None


def line_tail_shorthand(pattern: str) -> str | None:
    """Return the start expression in the shorthand ``^start$$`` form."""
    if not pattern.startswith("^") or not pattern.endswith("$$"):
        return None
    marker = len(pattern) - 2
    slashes = 0
    for char in reversed(pattern[:marker]):
        if char != "\\":
            break
        slashes += 1
    if slashes % 2:
        return None
    start = pattern[1:marker]
    return start or None


def line_tail_start_pattern(pattern: str) -> str | None:
    return line_tail_shorthand(pattern) or open_ended_line_pattern(pattern)


def leading_literal(pattern: str) -> str:
    """Return the plain-text prefix before the first regex operator."""
    literal: list[str] = []
    escaped = False
    escapable = set(r".\^$*+?{}[]|()")
    for char in pattern:
        if escaped:
            if char not in escapable:
                break
            literal.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
        elif char in ".^$*+?{}[]|()":
            break
        else:
            literal.append(char)
    return "".join(literal)


def regex_matches_latest(text: str, pattern: str) -> list[re.Match[str]]:
    """Return viable matches from newest start to oldest start."""
    compiled = re.compile(prose_friendly_pattern(pattern), re.MULTILINE | re.DOTALL)
    prefix = leading_literal(pattern)
    if prefix:
        prefix_pattern = re.compile(prose_friendly_pattern(re.escape(prefix)))
        starts = [candidate.start() for candidate in prefix_pattern.finditer(text)]
        matches = []
        for start in reversed(starts):
            candidate = compiled.match(text, start)
            if candidate is not None and candidate.end() > candidate.start():
                matches.append(candidate)
        return matches

    return [
        candidate
        for candidate in reversed(list(compiled.finditer(text)))
        if candidate.end() > candidate.start()
    ]


def latest_regex_match(text: str, pattern: str) -> re.Match[str] | None:
    """Prefer the latest viable start, including overlapping greedy ranges."""
    matches = regex_matches_latest(text, pattern)
    return matches[0] if matches else None


def find_latest_match(text: str, pattern: str, occurrence: int = 0) -> Match | None:
    """Match with multiline anchors and DOTALL, starting at the latest line."""
    clean = clean_scrollback(text)
    if not pattern or occurrence < 0:
        return None

    line_prefix = anchored_line_prefix(pattern)
    if line_prefix is not None:
        compiled_prefix = re.compile(prose_friendly_pattern(re.escape(line_prefix)))
        lines = clean.splitlines()
        matches = []
        for index in range(len(lines) - 1, -1, -1):
            occurrences = list(compiled_prefix.finditer(lines[index]))
            matches.extend(
                Match(lines[index], index, index) for _ in reversed(occurrences)
            )
        return matches[occurrence] if occurrence < len(matches) else None

    line_start_pattern = line_tail_start_pattern(pattern)
    if line_start_pattern is not None:
        lines = clean.splitlines()
        matches = []
        for index in range(len(lines) - 1, -1, -1):
            for found in regex_matches_latest(lines[index], line_start_pattern):
                matches.append(Match(lines[index][found.start() :], index, index))
        return matches[occurrence] if occurrence < len(matches) else None

    if pattern.startswith("^"):
        range_pattern = pattern[1:-1] if pattern.endswith("$") else pattern[1:]
        if not range_pattern:
            return None
        found_matches = regex_matches_latest(clean, range_pattern)
    else:
        found_matches = regex_matches_latest(clean, pattern)

    if occurrence >= len(found_matches):
        return None
    found = found_matches[occurrence]
    start_line = clean.count("\n", 0, found.start())
    end_line = clean.count("\n", 0, max(found.start(), found.end() - 1))
    return Match(found.group(0), start_line, end_line)


def inline_erase_count(trigger_length: int, initial_query: str) -> int:
    return max(0, trigger_length + len(initial_query) - len(INITIAL_QUERY))


def inline_query_from_capture(captured: str, cursor_x: int) -> str:
    """Recover a matcher suffix typed before the popup acquired focus."""
    current_row = captured.split("\n", 1)[0]
    before_cursor = current_row[:cursor_x]
    trigger_at = before_cursor.rfind(INLINE_TRIGGER)
    if trigger_at < 0:
        return INITIAL_QUERY
    return before_cursor[trigger_at + len(INLINE_TRIGGER) - len(INITIAL_QUERY) :]


def recover_inline_query(pane: str) -> str:
    cursor = tmux(
        "display-message",
        "-p",
        "-t",
        pane,
        "#{cursor_x}|#{cursor_y}",
        capture_output=True,
    ).stdout.strip()
    cursor_x, separator, cursor_y = cursor.partition("|")
    if not separator or not cursor_x.isdigit() or not cursor_y.isdigit():
        return INITIAL_QUERY
    captured = tmux(
        "capture-pane",
        "-p",
        "-N",
        "-S",
        cursor_y,
        "-E",
        cursor_y,
        "-t",
        pane,
        capture_output=True,
    ).stdout
    return inline_query_from_capture(captured, int(cursor_x))


def has_terminal_anchor(query: str) -> bool:
    if not query.endswith("$"):
        return False
    slashes = 0
    for char in reversed(query[:-1]):
        if char != "\\":
            break
        slashes += 1
    return slashes % 2 == 0


def space_action(query: str, has_match: bool) -> str:
    if not has_terminal_anchor(query):
        return "put( )"
    return "accept" if has_match else "no-match"


def run(
    command: list[str], *, check: bool = True, **kwargs
) -> subprocess.CompletedProcess:
    return subprocess.run(command, check=check, text=True, **kwargs)


def tmux(*args: str, check: bool = True, **kwargs) -> subprocess.CompletedProcess:
    return run(["tmux", *args], check=check, **kwargs)


def active_tmux_target() -> tuple[str, str]:
    """Resolve the tmux client hosted by the focused X11 terminal."""
    active_window = None
    try:
        active_window = int(
            run(["xdotool", "getactivewindow"], capture_output=True).stdout.strip()
        )
    except (FileNotFoundError, ValueError, subprocess.CalledProcessError):
        pass

    clients = tmux(
        "list-clients", "-F", "#{client_name}|#{client_pid}", capture_output=True
    ).stdout.splitlines()
    chosen = None
    if active_window is not None:
        for row in clients:
            client, _, pid = row.partition("|")
            try:
                environ = Path(f"/proc/{int(pid)}/environ").read_bytes().split(b"\0")
                value = next(
                    part[9:] for part in environ if part.startswith(b"WINDOWID=")
                )
                if int(value) == active_window:
                    chosen = client
                    break
            except (OSError, ValueError, StopIteration):
                continue
    if chosen is None and clients:
        chosen = clients[0].partition("|")[0]
    if not chosen:
        raise RuntimeError("no attached tmux client")

    pane = tmux(
        "display-message", "-p", "-c", chosen, "#{pane_id}", capture_output=True
    ).stdout.strip()
    if re.fullmatch(r"%\d+", pane) is None:
        raise RuntimeError("focused tmux client has no active pane")
    return chosen, pane


def state_path(state: str) -> Path:
    path = Path(state).resolve()
    if path.parent != Path(tempfile.gettempdir()) or not path.name.startswith(
        "pane-regex-expand-"
    ):
        raise ValueError("invalid state directory")
    return path


def write_match(state: Path, query: str, match: Match | None) -> None:
    target = state / "match.json"
    if match is None:
        target.unlink(missing_ok=True)
        return
    temp = state / "match.json.new"
    temp.write_text(json.dumps({"query": query, **asdict(match)}, ensure_ascii=False))
    temp.replace(target)


def read_match(state: Path, query: str) -> Match | None:
    try:
        payload = json.loads((state / "match.json").read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None
    if payload.pop("query", None) != query:
        return None
    return Match(**payload)


def ere_literal(text: str) -> str:
    return re.sub(r"([\\.\[\]{}()*+?^$|])", r"\\\1", text)


def native_highlight_pattern(query: str, match: Match | None = None) -> str:
    """Choose the stable single-line locator for tmux's native highlighter."""
    locator = anchored_line_prefix(query)
    if locator is not None:
        return prose_friendly_pattern(ere_literal(locator))
    line_start = line_tail_start_pattern(query)
    if line_start is not None:
        start = prose_friendly_pattern(line_start)
        return f"({start}.*[^[:space:]]|{start})"
    if query.startswith("^"):
        body = query[1:-1] if query.endswith("$") else query[1:]
        if match is not None and "\n" in match.text:
            prefix = leading_literal(body)
            if prefix:
                start = prose_friendly_pattern(ere_literal(prefix))
                return f"({start}.*[^[:space:]]|{start})"
            return prose_friendly_pattern(body)
        return prose_friendly_pattern(body)
    return prose_friendly_pattern(query)


def show_match(pane: str, query: str, match: Match | None, occurrence: int = 0) -> None:
    command = [
        "send-keys",
        "-X",
        "-t",
        pane,
        "history-bottom",
        ";",
        "send-keys",
        "-X",
        "-t",
        pane,
        "search-backward",
        "--",
        native_highlight_pattern(query, match),
    ]
    for _ in range(occurrence):
        command.extend([";", "send-keys", "-X", "-t", pane, "search-again"])
    tmux(*command, check=False)


def read_occurrence(state: Path) -> int:
    try:
        return max(0, int((state / "occurrence").read_text()))
    except (FileNotFoundError, ValueError):
        return 0


def update(pane: str, state_name: str, query: str) -> Match | None:
    state = state_path(state_name)
    with (state / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            previous_query = (state / "query").read_text()
        except FileNotFoundError:
            previous_query = None
        (state / "query").write_text(query)
        if previous_query != query or not (state / "occurrence").exists():
            (state / "occurrence").write_text("0")

        captured = tmux(
            "capture-pane", "-p", "-J", "-S", "-10000", "-t", pane, capture_output=True
        ).stdout
        try:
            match = find_latest_match(captured, query)
        except re.error:
            match = None
        write_match(state, query, match)
        show_match(pane, query, match)
        return match


def move_selection(pane: str, state_name: str, direction: str, query: str) -> None:
    if direction not in {"older", "newer"}:
        raise ValueError("invalid selection direction")

    state = state_path(state_name)
    with (state / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            current_query = (state / "query").read_text()
        except FileNotFoundError:
            current_query = ""
        occurrence = read_occurrence(state) if current_query == query else 0
        candidate = occurrence + 1 if direction == "older" else max(0, occurrence - 1)

        captured = tmux(
            "capture-pane",
            "-p",
            "-J",
            "-S",
            "-10000",
            "-t",
            pane,
            capture_output=True,
        ).stdout
        try:
            match = find_latest_match(captured, query, occurrence=candidate)
        except re.error:
            match = None
        if match is None:
            return

        (state / "query").write_text(query)
        (state / "occurrence").write_text(str(candidate))
        write_match(state, query, match)
        show_match(pane, query, match, occurrence=candidate)


def action_for_accept(pane: str, state_name: str, query: str, *, space: bool) -> str:
    state = state_path(state_name)
    if space and not has_terminal_anchor(query):
        return "put( )"
    try:
        current_query = (state / "query").read_text()
    except FileNotFoundError:
        current_query = ""
    match = read_match(state, query) if current_query == query else None
    found = match is not None or update(pane, state_name, query) is not None
    action = (
        space_action(query, found) if space else ("accept" if found else "no-match")
    )
    if action == "no-match":
        return "change-header(No match. Keep typing or press Esc)"
    return action


def cancel(pane: str) -> None:
    tmux("send-keys", "-X", "-t", pane, "cancel", check=False)


def accept(pane: str, state: Path, query: str) -> None:
    match = read_match(state, query)
    if match is None:
        cancel(pane)
        return
    match_file = state / "match.txt"
    match_file.write_text(match.text)
    cancel(pane)

    try:
        erase = int((state / "inline-length").read_text())
    except (FileNotFoundError, ValueError):
        erase = 0
    if erase:
        tmux("send-keys", "-t", pane, "-N", str(erase), "BSpace")
    run(["bash", str(DELIVER), "--file", pane, str(match_file)])


def watch_queries(pane: str, state_name: str) -> int:
    state = state_path(state_name)
    last = None
    while state.is_dir() and not (state / "stop").exists():
        try:
            desired = (state / "desired").read_text()
        except FileNotFoundError:
            time.sleep(0.02)
            continue
        if desired != last:
            update(pane, state_name, desired)
            last = desired
        time.sleep(0.02)
    return 0


def fzf_command(pane: str, state: Path, initial_query: str) -> list[str]:
    base = [sys.executable, str(SCRIPT)]
    desired_new = shlex.quote(str(state / "desired.new"))
    desired = shlex.quote(str(state / "desired"))
    record_query = (
        f"printf %s {{q}} > {desired_new} && mv -f -- {desired_new} {desired}"
    )
    accept_command = shlex.join([*base, "--accept-action", pane, str(state)]) + " {q}"
    space_command = shlex.join([*base, "--space-action", pane, str(state)]) + " {q}"
    older_command = shlex.join([*base, "--move", pane, str(state), "older"]) + " {q}"
    newer_command = shlex.join([*base, "--move", pane, str(state), "newer"]) + " {q}"
    return [
        "fzf",
        "--disabled",
        "--layout=reverse",
        "--no-info",
        "--no-separator",
        "--no-scrollbar",
        "--pointer=",
        "--marker=",
        "--prompt=regex> ",
        "--header=Up older. Down newer. Tab or Enter expands. Space after $ expands.",
        f"--query={initial_query}",
        "--print-query",
        "--bind",
        f"start,change:execute-silent({record_query})",
        "--bind",
        f"tab,enter:transform({accept_command})",
        "--bind",
        f"space:transform({space_command})",
        "--bind",
        f"up:execute-silent({older_command})",
        "--bind",
        f"down:execute-silent({newer_command})",
    ]


def prompt(pane: str, state_name: str, trigger_length: int) -> int:
    state = state_path(state_name)
    initial_query = recover_inline_query(pane)
    (state / "query").write_text(initial_query)
    (state / "desired").write_text(initial_query)
    (state / "inline-length").write_text(
        str(inline_erase_count(trigger_length, initial_query))
    )
    tmux("copy-mode", "-t", pane)
    watcher = subprocess.Popen(
        [sys.executable, str(SCRIPT), "--watch", pane, str(state)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        result = run(
            fzf_command(pane, state, initial_query),
            input="\n",
            capture_output=True,
            check=False,
        )
    finally:
        (state / "stop").touch()
        try:
            watcher.wait(timeout=1)
        except subprocess.TimeoutExpired:
            watcher.terminate()
            watcher.wait(timeout=1)
    if result.returncode != 0:
        cancel(pane)
        return 0
    query = result.stdout.splitlines()[0] if result.stdout else ""
    accept(pane, state, query)
    return 0


def start(trigger_length: int) -> int:
    if trigger_length <= 0:
        return 0
    _, pane = active_tmux_target()
    state = Path(tempfile.mkdtemp(prefix="pane-regex-expand-"))
    (state / "query").write_text(INITIAL_QUERY)
    try:
        command = shlex.join(
            [
                sys.executable,
                str(SCRIPT),
                "--prompt",
                pane,
                str(state),
                str(trigger_length),
            ]
        )
        tmux(
            "display-popup",
            "-E",
            "-t",
            pane,
            "-x",
            "C",
            "-y",
            "0",
            "-w",
            "90%",
            "-h",
            "7",
            "-T",
            " pane regex ",
            command,
        )
    finally:
        cancel(pane)
        shutil.rmtree(state, ignore_errors=True)
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("trigger_length", nargs="?", type=int, default=3)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--prompt", nargs=3, metavar=("PANE", "STATE", "TRIGGER_LENGTH"))
    modes.add_argument("--watch", nargs=2, metavar=("PANE", "STATE"))
    modes.add_argument("--accept-action", nargs=3, metavar=("PANE", "STATE", "QUERY"))
    modes.add_argument("--space-action", nargs=3, metavar=("PANE", "STATE", "QUERY"))
    modes.add_argument(
        "--move", nargs=4, metavar=("PANE", "STATE", "DIRECTION", "QUERY")
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.prompt:
        pane, state, trigger_length = args.prompt
        return prompt(pane, state, int(trigger_length))
    if args.watch:
        pane, state = args.watch
        return watch_queries(pane, state)
    if args.accept_action:
        pane, state, query = args.accept_action
        print(action_for_accept(pane, state, query, space=False))
        return 0
    if args.space_action:
        pane, state, query = args.space_action
        print(action_for_accept(pane, state, query, space=True))
        return 0
    if args.move:
        pane, state, direction, query = args.move
        move_selection(pane, state, direction, query)
        return 0
    return start(args.trigger_length)


if __name__ == "__main__":
    raise SystemExit(main())
