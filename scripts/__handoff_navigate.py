#!/usr/bin/env python3
"""Resolve one handoff destination and open it beside the editable brief."""
import json
import fcntl
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time
from urllib.parse import parse_qs, quote, urlsplit

ROOT = Path(__file__).resolve().parent
# One workspace, two permalink hosts: since the Enterprise Grid move Slack hands
# out vcluster-internal.enterprise links beside the older loft-labs-inc ones.
SLACK_HOSTS = {"loft-labs-inc.slack.com", "vcluster-internal.enterprise.slack.com"}
HOSTS = SLACK_HOSTS | {"app.slack.com", "github.com", "linear.app",
                       "mail.google.com", "app.notion.com", "docs.google.com", "claude.ai"}
UUID = re.compile(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")


def checked_url(url, *, any_host=False):
    """Reject ambiguous authorities and schemes before any process is launched."""
    if any(ord(c) <= 32 or ord(c) == 127 for c in url) or "\\" in url:
        raise ValueError("Invalid destination URL")
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or not parsed.hostname or (not any_host and parsed.hostname not in HOSTS)
            or parsed.username is not None or parsed.password is not None
            or parsed.port is not None):
        raise ValueError("Handoff destination must use an allowed HTTPS host")
    return url


def single_url(text, *, any_host=False):
    """Read one URL, allowing a Markdown link or a terminal sentence period."""
    urls = list(dict.fromkeys(u.rstrip(".,;") for u in re.findall(r"https?://[^\s<>\])]+", text)))
    if len(urls) != 1:
        raise ValueError("Handoff needs one destination in target: or link:")
    return checked_url(urls[0], any_host=any_host)


def mail_sent_url(done):
    """Find the newest message and its mail account for a mail-sent condition."""
    match = re.match(r"^mail-sent\s+([0-9a-fA-F]+)(?:\s|$)", done)
    if not match:
        return None
    try:
        messages = run(["notmuch", "search", "--output=messages", "--sort=newest-first",
                        "thread:" + match.group(1)], capture_output=True, text=True).stdout.splitlines()
        if not messages or not messages[0].startswith("id:") or not messages[0][3:]:
            return None
        message = messages[0][3:]
        files = run(["notmuch", "search", "--output=files", messages[0]],
                    capture_output=True, text=True).stdout.splitlines()
        root = Path.home() / ".local/share/mail"
        for name in files:
            try:
                parts = Path(name).relative_to(root).parts
            except ValueError:
                continue
            if len(parts) >= 2 and ".." not in parts:
                return checked_url(f"https://mail.google.com/mail/?authuser={quote(parts[0], safe='@')}"
                                   f"#search/rfc822msgid%3A{quote(message, safe='')}")
    except (OSError, subprocess.SubprocessError):
        return None
    return None


def destination(task):
    """Use the newest explicit field; never follow links embedded in a draft."""
    if "piotr" not in task.get("tags", []):
        return None
    fields = {}
    for annotation in sorted(task.get("annotations", []), key=lambda a: a.get("entry", "")):
        key, sep, value = annotation.get("description", "").partition(":")
        if sep and key.lower() in {"target", "link", "tab", "done-when"}:
            fields[key.lower()] = value.strip()
    if "tab" in fields:
        return single_url(fields["tab"], any_host=True)
    if "target" in fields:
        target = fields["target"]
        slack = re.match(r"slack:([CDG][A-Z0-9]+)/(top|[0-9]+\.[0-9]{6})(?:\s|$)", target)
        if slack:
            channel, stamp = slack.groups()
            canonical = f"https://loft-labs-inc.slack.com/archives/{channel}"
            if stamp != "top":
                canonical += f"/p{stamp.replace('.', '')}"
            if "http" in target:
                supplied = single_url(target)
                parsed = urlsplit(supplied)
                path = re.fullmatch(rf"/archives/{re.escape(channel)}/p[0-9]+", parsed.path)
                thread = parse_qs(parsed.query).get("thread_ts", [])
                matches = (parsed.path.rstrip('/') == urlsplit(canonical).path or path
                           if stamp == "top" else
                           path and (parsed.path == urlsplit(canonical).path or thread == [stamp]))
                if parsed.hostname not in SLACK_HOSTS or not matches:
                    uuid = task.get("uuid") or os.environ.get("HANDOFF_TASK_UUID")
                    suffix = f" (task {uuid})" if uuid else " (task UUID unavailable)"
                    raise ValueError("Slack target and permalink disagree" + suffix)
                return supplied
            return canonical if stamp == "top" else canonical + "?thread_ts=" + stamp
        return single_url(target)
    if "link" in fields:
        return single_url(fields["link"])
    done = fields.get("done-when", "")
    if re.match(r"^mail-sent(?:\s|$)", done):
        return mail_sent_url(done)
    if "http" in done:
        return single_url(done)
    prs = re.findall(r"\b((?:[A-Za-z0-9_.-]+/)?[A-Za-z0-9_.-]+)#([1-9][0-9]*)\b", done)
    if len(set(prs)) == 1:
        repo, number = prs[0]
        if "/" not in repo:
            repo = "loft-sh/" + repo
        return checked_url(f"https://github.com/{repo}/pull/{number}")
    issues = set(re.findall(r"\b[A-Z][A-Z0-9]+-[1-9][0-9]*\b", done))
    if len(issues) == 1 and not prs:
        return checked_url(f"https://linear.app/loft/issue/{issues.pop()}")
    if prs or issues:
        raise ValueError("Handoff has multiple destinations; add one target: annotation")
    return None


def run(argv, timeout=15, **kwargs):
    """Keep argument boundaries intact and bound external commands."""
    return subprocess.run([str(a) for a in argv], timeout=timeout, check=True, **kwargs)


def log(line):
    """Report on stderr and in a state log; the task hook discards stderr."""
    print(line, file=sys.stderr)
    path = Path(os.environ.get("HANDOFF_NAV_LOG", str(
        Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "handoff-navigate.log")))
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as handle:
            handle.write(time.strftime("%Y-%m-%dT%H:%M:%S%z ") + line + "\n")
    except OSError:
        pass


def window_id(window_class):
    """Capture the active matching managed window before navigation changes focus."""
    try:
        windows = run(["wmctrl", "-lx"], capture_output=True, text=True).stdout.splitlines()
        ids = [str(int(line.split()[0], 16)) for line in windows
               if len(line.split()) > 2 and window_class in line.split()[2].lower()]
        active = run(["xdotool", "getactivewindow"], capture_output=True, text=True).stdout.strip()
        return active if active in ids else (ids[0] if ids else "")
    except (OSError, subprocess.SubprocessError, ValueError):
        return ""


def terminal_monitor(terminal):
    """Find the connected output containing the source window's center."""
    if not terminal:
        log("handoff: terminal xid=missing geometry=missing monitor=missing")
        return ""
    geometry = "missing"
    try:
        windows = run(["wmctrl", "-lG"], capture_output=True, text=True).stdout.splitlines()
        for line in windows:
            fields = line.split()
            if len(fields) >= 6 and int(fields[0], 16) == int(terminal):
                x, y, width, height = map(int, fields[2:6])
                geometry = f"{x},{y},{width},{height}"
                cx, cy = x + width // 2, y + height // 2
                break
        else:
            log(f"handoff: terminal xid={terminal} geometry={geometry} monitor=missing")
            return ""
        outputs = run(["xrandr", "--current"], capture_output=True, text=True).stdout.splitlines()
        nearest = None
        for line in outputs:
            match = re.match(r"(\S+) connected (?:primary )?(\d+)x(\d+)([+-]\d+)([+-]\d+)", line)
            if match:
                name, w, h, x, y = match.groups()
                if int(x) <= cx < int(x) + int(w) and int(y) <= cy < int(y) + int(h):
                    log(f"handoff: terminal xid={terminal} geometry={geometry} monitor={name}")
                    return name
                dx = max(int(x) - cx, 0, cx - (int(x) + int(w) - 1))
                dy = max(int(y) - cy, 0, cy - (int(y) + int(h) - 1))
                candidate = (dx * dx + dy * dy, name)
                if nearest is None or candidate < nearest:
                    nearest = candidate
        if nearest:
            log(f"handoff: terminal xid={terminal} geometry={geometry} monitor={nearest[1]} (nearest)")
            return nearest[1]
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        log(f"handoff: terminal lookup error={type(error).__name__}")
    log(f"handoff: terminal xid={terminal} geometry={geometry} monitor=missing")
    return ""


def slack_deep_link(url):
    """Convert a workspace channel or message URL to a desktop link."""
    parsed = urlsplit(checked_url(url))
    match = re.fullmatch(r"/archives/([CDG][A-Z0-9]+)(?:/p([0-9]{7,}))?/?", parsed.path)
    if parsed.hostname not in SLACK_HOSTS or not match:
        raise ValueError("Unsupported Slack destination; use a channel or message permalink")
    team = os.environ.get("SLACK_TEAM_ID", "")
    config = Path(os.environ.get("SLACK_OPEN_TEAMS_CONFIG", str(
        Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "slack-open/teams")))
    if not team and config.is_file():
        for line in config.read_text().splitlines():
            parts = line.split()
            # Both permalink hosts address this workspace; the desktop app maps its
            # team ID to the enterprise org.
            if len(parts) >= 2 and parts[0] == "loft-labs-inc":
                team = parts[1]
                break
    if not re.fullmatch(r"T[A-Z0-9]+", team):
        raise ValueError("Slack team ID missing; configure slack-open/teams")
    channel, raw_ts = match.groups()
    link = f"slack://channel?team={team}&id={channel}"
    if raw_ts:
        link += f"&message={raw_ts[:-6]}.{raw_ts[-6:]}"
    thread = parse_qs(parsed.query).get("thread_ts", [])
    if raw_ts and not thread:
        thread = [f"{raw_ts[:-6]}.{raw_ts[-6:]}"]
    if thread:
        if len(thread) != 1 or not re.fullmatch(r"[0-9]+\.[0-9]{6}", thread[0]):
            raise ValueError("Invalid Slack thread timestamp")
        link += f"&thread_ts={thread[0]}"
    return link


def open_page(url):
    """Open one page as a background tab in the existing Chrome window, bridge first.

    A stale bridge extension exits 1; xdg-open still reaches the page (11 Nov).
    The bridge gets about a second: a bridge that accepted the request and never
    answered held s for its full timeout first (Piotr, 11 Nov: the right mail
    "but with huge delay"). No --focus, so the broker neither raises nor tiles
    Chrome, and neither path asks for a new window.
    """
    try:
        timeout = float(os.environ.get("HANDOFF_TAB_TIMEOUT", "1"))
    except ValueError:
        timeout = 1.0
    try:
        run([os.environ.get("HANDOFF_TAB_COMMAND", str(ROOT / "__handoff_tab.py")), url],
            timeout=timeout, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        log(f"handoff: opened via tab bridge {url}")
    except (OSError, subprocess.SubprocessError) as error:
        detail = getattr(error, "stderr", None) or str(error)
        if isinstance(detail, bytes):
            detail = detail.decode(errors="replace")
        log(f"handoff: tab bridge error: {detail.strip()}")
        log(f"handoff: tab bridge failed, fallback xdg-open {url}")
        run(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def navigate_many(urls, terminal, slack_tabs=False):
    """Open each URL and tile its browser or Slack window beside the terminal.

    slack_tabs opens Slack permalinks as browser tabs too: a draft row is pasted
    into the thread in Chrome.
    """
    urls = list(dict.fromkeys(urls))
    env = dict(os.environ, LAYOUT_ALACRITTY_WINDOW=terminal)
    is_slack = lambda u: urlsplit(u).hostname in SLACK_HOSTS | {"app.slack.com"}
    desktop = [] if slack_tabs else [u for u in urls if is_slack(u)]
    pages = [u for u in urls if u not in desktop]
    for url in desktop:
        deep_link = slack_deep_link(url)
        log(f"handoff: opening desktop {deep_link}")
        run(["xdg-open", deep_link], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    browser = os.environ.get("HANDOFF_BROWSER_COMMAND")
    if browser and pages:
        run([browser, *pages])
    else:
        for page in pages:
            open_page(page)
    if desktop or pages:
        monitor = terminal_monitor(terminal)
        if not terminal or not monitor:
            log("handoff: cannot tile without the source terminal and its monitor")
            return
        env["LAYOUT_MONITOR"] = monitor
        if pages and not desktop:
            browser_id = window_id("google-chrome")
            if not terminal or not browser_id:
                log("handoff: cannot tile without the source terminal and Chrome window")
                return
            env["LAYOUT_BROWSER_WINDOW"] = browser_id
        run([os.environ.get("HANDOFF_LAYOUT_COMMAND", str(ROOT / "__layouts.sh")),
             "8" if desktop else "2"], env=env, stdout=subprocess.DEVNULL)


SESSION_NOTE = re.compile(r"\btmux session ([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*)")


def agent_sessions(task):
    """Return declared agent sessions, newest first: `agent:` notes and `tmux session <name>`."""
    names = []
    for annotation in sorted(task.get("annotations", []), key=lambda a: a.get("entry", "")):
        text = annotation.get("description", "")
        key, sep, value = text.partition(":")
        if sep and key.strip().lower() == "agent" and value.strip():
            names.append(value.strip())
        names.extend(SESSION_NOTE.findall(text))
    return list(dict.fromkeys(reversed(names)))


def agent_session(task):
    """Return the newest declared agent session without checking that it lives."""
    sessions = agent_sessions(task)
    return sessions[0] if sessions else ""


def live_agent_session(task):
    """Return the newest declared session tmux has-session confirms, or ''."""
    tmux = os.environ.get("HANDOFF_TMUX_COMMAND", "tmux")
    for session in agent_sessions(task):
        if any(ord(char) < 32 or ord(char) == 127 for char in session):
            continue
        try:
            if subprocess.run([tmux, "has-session", "-t", "=" + session], timeout=5,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                return session
        except (OSError, subprocess.SubprocessError):
            continue
    return ""


def annotation_urls(task):
    """Return the latest target, every explicit link note in task order, then the cmd_page."""
    annotations = sorted(task.get("annotations", []), key=lambda a: a.get("entry", ""))
    target_rows = [a for a in annotations
                   if re.match(r"^\s*target:\s*\S", a.get("description", ""), re.I)]
    urls = []
    if target_rows:
        try:
            urls.append(destination({"uuid": task.get("uuid"), "tags": ["piotr"],
                                     "annotations": [target_rows[-1]]}))
        except ValueError as error:
            print(f"Could not open handoff destination: {error}", file=sys.stderr)
    for annotation in annotations:
        match = re.match(r"^\s*(?:link|tab):\s*(.*)$", annotation.get("description", ""), re.I)
        if match:
            try:
                urls.append(single_url(match.group(1), any_host=annotation.get("description", "").lstrip().lower().startswith("tab:")))
            except ValueError as error:
                print(f"Could not open handoff destination: {error}", file=sys.stderr)
    urls.append(cmd_page(task))
    return list(dict.fromkeys(url for url in urls if url))


def cmd_page(task):
    """Return the page a legacy `cmd: xdg-open <url>` note opens, or ''."""
    try:
        args = shlex.split(newest_note(task, "cmd"))
        if len(args) == 2 and args[0] == "xdg-open":
            return checked_url(args[1], any_host=True)
    except ValueError:
        pass
    return ""


KINDS = {"slack", "command", "pr", "ack", "other"}
# The fixed line puts the row's command in the next editing buffer, unsubmitted,
# and arms a one-shot hook: the first command Piotr runs there that exits 0
# calls `verify` (Piotr, 11 Nov: "once command is ran verify it and close task").
PREFILL = (' xdg-open() { command xdg-open "$@" > >(sed \"/^[Oo]pening in existing browser session\\.$/d\") 2> >(sed -E \"/zygote_linux\\.cc:.*Broken pipe|zygote_main_linux\\.cc:.*Broken pipe/d\" >&2); };'
           ' handoff_ran() { HANDOFF_RAN=1; };'
           ' handoff_rc() { local rc=$?; [[ -n $HANDOFF_RAN ]] || return 0; unset HANDOFF_RAN;'
           ' (( rc == 0 )) || return 0;'
           ' precmd_functions=(${precmd_functions:#handoff_rc});'
           ' preexec_functions=(${preexec_functions:#handoff_ran});'
           ' "$HANDOFF_NAVIGATOR" verify "$HANDOFF_UUID"; };'
           ' preexec_functions+=(handoff_ran); precmd_functions+=(handoff_rc);'
           ' print -rz -- "$HANDOFF_CMD"; unset HANDOFF_CMD; clear')
# The floating pane geometry the brief floater uses (__handoff_floater.sh).
FLOAT = ["-x", "90%", "-y", "65%", "-X", "5%", "-Y", "30%"]


def newest_note(task, key):
    """Return the newest `key:` note's text, inner lines kept, or ''."""
    pattern = re.compile(rf"^\s*{re.escape(key)}:[^\S\n]*", re.I)
    values = [pattern.sub("", a.get("description", ""), count=1)
              for a in sorted(task.get("annotations", []), key=lambda a: a.get("entry", ""))
              if pattern.match(a.get("description", ""))]
    return values[-1].strip() if values else ""


def task_kind(task):
    """Read the row's kind; rows written before the field keep their actions."""
    kind = task.get("kind", "")
    if kind in KINDS:
        return kind
    if "draft" in task.get("tags", []):
        return "slack"
    return "command" if newest_note(task, "cmd") else "other"


def copy_to_clipboard(text):
    """Copy text with wl-copy on Wayland, falling back to xclip."""
    commands = [[os.environ.get("HANDOFF_XCLIP_COMMAND", "xclip"), "-selection", "clipboard"]]
    if os.environ.get("WAYLAND_DISPLAY"):
        commands.insert(0, [os.environ.get("HANDOFF_WLCOPY_COMMAND", "wl-copy")])
    for argv in commands:
        try:
            run(argv, input=text, text=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except (OSError, subprocess.SubprocessError):
            continue
    return False


def slack_row(task):
    """A +draft row or a slack kind: the only rows whose brief floater opens on s."""
    return "draft" in task.get("tags", []) or task_kind(task) == "slack"


def origin_pane():
    pane = os.environ.get("TMUX_PANE", "")
    if not re.fullmatch(r"%[0-9]+", pane):
        raise ValueError("no tmux pane to open the floating window over; press s in the handoffs view")
    return pane


def open_floating(title, argv, focus=True):
    """Open a floating tmux pane over the handoffs view; it takes the keyboard unless focus is False."""
    tmux = os.environ.get("HANDOFF_TMUX_COMMAND", "tmux")
    flags = ["-P", "-F", "#{pane_id}"] + ([] if focus else ["-d"])
    # Multiple argv elements bypass tmux's shell-string path.
    pane = run([tmux, "new-pane", *flags, "-t", origin_pane(), *FLOAT, "-T", title, "--", *argv],
               capture_output=True, text=True).stdout.strip()
    if not re.fullmatch(r"%[0-9]+", pane):
        raise ValueError("tmux did not report the floating pane")
    return pane


def open_command_window(uuid, command, focus=True):
    """Queue the command for Enter in a tmux window that stays open."""
    if not command:
        raise ValueError("command handoff has no cmd: note; add one with __tw.sh note <ref> 'cmd: <command>'")
    if any(ord(char) < 32 or ord(char) == 127 for char in command):
        raise ValueError("cmd: note must be one line without control characters")
    tmux = os.environ.get("HANDOFF_TMUX_COMMAND", "tmux")
    argv = ["env", "HANDOFF_CMD=" + command, "HANDOFF_UUID=" + uuid,
            "HANDOFF_NAVIGATOR=" + str(Path(__file__).resolve()), "zsh", "-i"]
    if re.fullmatch(r"%[0-9]+", os.environ.get("TMUX_PANE", "")):
        flags = [] if focus else ["-d"]
        pane = run([tmux, "new-window", "-P", "-F", "#{pane_id}", *flags,
                    "-t", origin_pane(), "-n", "handoff-" + uuid[:8], *argv],
                   capture_output=True, text=True).stdout.strip()
        if not re.fullmatch(r"%[0-9]+", pane):
            raise ValueError("tmux did not report the new window pane")
    else:
        pane = open_floating("handoff cmd " + uuid[:8], argv, focus)
    run([tmux, "send-keys", "-t", pane, "-l", PREFILL])
    run([tmux, "send-keys", "-t", pane, "Enter"])
    return pane


def attach_agent_session(session):
    """Attach a live agent session inside a focused floating pane."""
    tmux = os.environ.get("HANDOFF_TMUX_COMMAND", "tmux")
    current = run([tmux, "display-message", "-p", "-t", origin_pane(), "#{session_name}"],
                  capture_output=True, text=True).stdout.strip()
    if current == session:
        raise ValueError(f"agent session {session} is the session s was pressed in")
    # A nested client needs TMUX unset; tmux refuses to nest otherwise.
    pane = open_floating("agent " + session, ["env", "-u", "TMUX", tmux, "attach-session", "-t", "=" + session])
    run([tmux, "select-pane", "-t", pane])
    return pane


def act_on_kind(task, slack=False):
    """Run what s means for the row once its links are open; returns what it did.

    slack: copy the newest draft: (its brief floater shows the draft); a cmd: also
    waits unfocused, since the draft keeps the keyboard. command: the cmd: waits
    for Enter in a separate tmux window. agent: the newest live `agent:` or
    `tmux session <name>` session is attached in a focused floating pane.
    none: nothing applied. failed: the action was logged with its remedy.
    """
    kind = task_kind(task)
    slack = slack or slack_row(task)
    command = newest_note(task, "cmd")
    # annotation_urls already opened a cmd_page, so it needs no window.
    runnable = not cmd_page(task) and (command or kind == "command")
    try:
        if slack:
            draft = newest_note(task, "draft")
            if draft and not copy_to_clipboard(draft):
                log("Could not copy the draft: install xclip or wl-copy, then press s again.")
            if runnable:
                open_command_window(task["uuid"], command, focus=False)
            return "slack"
        if runnable:
            open_command_window(task["uuid"], command)
            return "command"
        session = live_agent_session(task)
        if session:
            attach_agent_session(session)
            return "agent"
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        log(f"handoff: {kind} action on {task.get('uuid')} failed: {error}")
        return "failed"
    return "none"


def verify(task):
    """After the row's cmd: exits 0, let its done-when probe close the row with proof.

    The probe (__handoff_probe.py run) owns the evidence and the close; a row
    without a machine-checkable done-when, or one the probe does not prove,
    stays open with a note saying why.
    """
    uuid = task["uuid"]
    tw = os.environ.get("HANDOFF_TW_WRAPPER", str(Path.home() / ".claude/scripts/__tw.sh"))
    probe = newest_note(task, "done-when")
    if not probe or probe.split()[0].lower() == "manual":
        why = "no machine-checkable done-when"
    else:
        try:
            result = subprocess.run([os.environ.get("HANDOFF_PROBE_COMMAND",
                                                    str(Path.home() / ".claude/scripts/__handoff_probe.py")),
                                     "run", "--uuid", uuid], capture_output=True, text=True, timeout=120)
            lines = [line for line in result.stdout.splitlines() if line.startswith(uuid[:8])]
            verdict = (lines or [result.stderr.strip() or f"probe exit {result.returncode}"])[-1]
            if result.returncode == 2:
                log(f"handoff: closed {uuid[:8]} by done-when probe: {verdict}")
                return 0
            why = f"done-when not proved ({verdict})"
        except (OSError, subprocess.SubprocessError) as error:
            why = f"done-when probe failed ({error})"
    # A timer can close the row before or during our probe. An empty probe
    # result is not evidence that it remained pending.
    def current():
        rows = task_export(os.environ.get("HANDOFF_TASK_COMMAND", "task"), uuid)
        if len(rows) != 1 or rows[0].get("uuid", "").lower() != uuid.lower():
            raise ValueError("task state unavailable")
        return rows[0]

    def closed(row):
        if row.get("status") == "completed":
            proof = newest_note(row, "done-when proved")
            actor = "done-when probe" if "__handoff_probe.py" in proof else "another action (actor unknown)"
            log(f"handoff: {uuid[:8]} already closed by {actor}")
            return True
        return False

    try:
        if closed(current()):
            return 0
        note = f"s: cmd exited 0; {why}; row stays open"
        result = subprocess.run([tw, "--all", "note", uuid, note], capture_output=True, text=True, timeout=15)
        if closed(current()):
            return 0
        if result.returncode:
            detail = (result.stderr or result.stdout).strip().splitlines()
            log(f"handoff: {uuid[:8]} could not save result: {detail[-1] if detail else 'note failed'}")
            return 1
        log(f"handoff: {uuid[:8]} {note}")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        log(f"handoff: {uuid[:8]} could not check or save result: {type(error).__name__}")
    return 1


def wait_for_slack_focus():
    """Wait briefly for the desktop app to raise itself before restoring the draft."""
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        try:
            slack = window_id("slack")
            active = run(["xdotool", "getactivewindow"], capture_output=True, text=True).stdout.strip()
            if slack and active == slack:
                return
        except (OSError, subprocess.SubprocessError):
            return
        time.sleep(0.1)


def show_slack_draft(pane, terminal, runtime):
    """Position the pinned brief at its draft and restore its terminal window."""
    if re.fullmatch(r"%[0-9]+", pane):
        socket = runtime / ("handoff-" + pane[1:] + ".sock")
        expression = ("luaeval(\"(function() local l=vim.api.nvim_buf_get_lines(0,0,-1,false); "
                      "for i=#l,1,-1 do if l[i]=='<!-- begin generated draft -->' then "
                      "vim.api.nvim_win_set_cursor(0,{math.min(i+2,#l),0}); "
                      "vim.cmd('normal! zz'); return true end end return false end)()\")")
        try:
            run([os.environ.get("HANDOFF_NVIM_COMMAND", "nvim"), "--server", socket,
                 "--remote-expr", expression], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError) as error:
            print(f"Could not position handoff draft: {error}", file=sys.stderr)
    if terminal:
        try:
            run(["xdotool", "windowactivate", terminal], stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError) as error:
            print(f"Could not restore terminal focus: {error}", file=sys.stderr)


def open_block(path):
    """Read only the editable generated block; never interpret the draft.

    Prepare skips writing the block while the editor holds the brief, so a
    missing block opens the task's own links instead of nothing (9 Nov).
    """
    text = Path(path).read_text()
    match = re.search(r"<!-- begin open -->[^\S\n]*\n(.*?)\n<!-- end open -->", text, re.S)
    if not match:
        return []
    return [checked_url(line.strip()) for line in match.group(1).splitlines() if line.strip()]


def task_export(task_bin, *filters):
    result = run([task_bin, "rc.context=none", "rc.hooks=off", "rc.verbose=nothing",
                  "rc.gc=off", *filters, "export"], capture_output=True, text=True)
    return json.loads(result.stdout)


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    mode = args.pop(0) if args and args[0] in {"start", "stop", "verify"} else "start"
    if not args or not UUID.fullmatch(args[0]):
        print("Select a handoff using its full task UUID.", file=sys.stderr)
        return 2
    uuid = args[0]
    task_bin = os.environ.get("HANDOFF_TASK_COMMAND", "task")
    if mode == "verify":
        rows = task_export(task_bin, uuid)
        if len(rows) != 1 or rows[0].get("uuid", "").lower() != uuid.lower():
            raise ValueError("Task UUID did not resolve to exactly one task")
        return verify(rows[0])
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "taskwarrior-tui"
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    state = runtime / "handoff-work.json"
    floater = Path(os.environ.get("HANDOFF_FLOATER_COMMAND", str(ROOT / "__handoff_floater.sh")))
    with (runtime / "handoff-work.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        old = json.loads(state.read_text()) if state.exists() else {}
        if mode == "stop":
            if old.get("uuid") != uuid:
                return 0
            run([floater, "close", uuid, old["pane"]])
            if old.get("terminal"):
                run([os.environ.get("HANDOFF_LAYOUT_COMMAND", str(ROOT / "__layouts.sh")), "1"],
                    env=dict(os.environ, LAYOUT_ALACRITTY_WINDOW=old["terminal"]), stdout=subprocess.DEVNULL)
            state.unlink(missing_ok=True)
            return 0
        # The hook starts us before Taskwarrior commits the modification.
        # Wait briefly for the start to become visible in the database.
        for attempt in range(40):
            rows = task_export(task_bin, uuid)
            if mode != "start" or "--resolve" in args or (rows and (rows[0].get("start") or "piotr" not in rows[0].get("tags", []))):
                break
            time.sleep(0.05)
        if len(rows) != 1 or rows[0].get("uuid", "").lower() != uuid.lower():
            raise ValueError("Task UUID did not resolve to exactly one task")
        task = rows[0]
        if "piotr" not in task.get("tags", []):
            return 0
        if "--resolve" in args:
            url = destination(task)
            if url:
                print(url)
            return 0
        # This detached process runs after the originating hook returns. Check
        # current state again, and stop other starts without reentering hooks.
        if not task.get("start"):
            return 0
        # A row carrying +claude or +codex was started by an agent spawn (key 4),
        # not by S. Leave it running; only Piotr's own starts take turns.
        active = [row for row in task_export(task_bin, "+piotr", "status:pending", "+ACTIVE")
                  if row.get("uuid") == uuid or not {"claude", "codex"} & set(row.get("tags", []))]
        # A delayed navigator must never stop a newer start. UUID breaks ties
        # when Taskwarrior records multiple starts in the same second.
        winner = max(active, key=lambda row: (row.get("start", ""), row.get("uuid", "")), default=None)
        if not winner:
            return 0
        for other in active:
            if other.get("uuid") != winner.get("uuid"):
                run([task_bin, "rc.context=none", "rc.hooks=off", "rc.confirmation=no",
                     other["uuid"], "stop"], stdout=subprocess.DEVNULL)
        if winner.get("uuid") != uuid:
            return 0
        pane = os.environ.get("TMUX_PANE", "")
        terminal = window_id("alacritty")
        # Piotr, 11 Nov 12:44: "do not open the floating window brief for
        # anything else than slack". Other rows act directly.
        slack = slack_row(task)
        if old and old.get("uuid") != uuid and (old.get("pane") != pane or not slack):
            run([floater, "close", old["uuid"], old["pane"]])
        state.write_text(json.dumps({"uuid": uuid, "pane": pane, "terminal": terminal}))
        try:
            prepared = run([floater, "prepare", uuid, pane], capture_output=True, text=True,
                           env=dict(os.environ, HANDOFF_TASK_UUID=uuid)).stdout.strip()
            urls = open_block(prepared)
            for url in annotation_urls(task):
                if url not in urls:
                    urls.append(url)
            if not urls:
                fallback_task = dict(task, annotations=[a for a in task.get("annotations", [])
                    if not re.match(r"^\s*(target|link):", a.get("description", ""), re.I)])
                fallback = destination(fallback_task)
                urls = [fallback] if fallback else []
            navigate_many(urls, terminal)
            if act_on_kind(task, slack) == "none" and not urls:
                # Nothing to open or run: Gordon fixes the row (link:, cmd: or agent:).
                log(f"handoff: no action on {uuid}")
        finally:
            if slack:
                run([floater, "pin", uuid, pane])
        if slack:
            if any(urlsplit(url).hostname in SLACK_HOSTS for url in urls):
                wait_for_slack_focus()
            show_slack_draft(pane, terminal, runtime)
            if re.fullmatch(r"%[0-9]+", pane):
                # A cmd: pane may hold the keyboard; the draft brief takes it back.
                run([os.environ.get("HANDOFF_TMUX_COMMAND", "tmux"), "select-window", "-t", pane])
                run([floater, "focus", uuid, pane])
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Handoff navigation: {error}", file=sys.stderr)
        sys.exit(1)
