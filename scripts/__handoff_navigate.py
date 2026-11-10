#!/usr/bin/env python3
"""Resolve one handoff destination and open it beside the editable brief."""
import json
import fcntl
import os
from pathlib import Path
import re
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


def checked_url(url):
    """Reject ambiguous authorities and schemes before any process is launched."""
    if any(ord(c) <= 32 or ord(c) == 127 for c in url) or "\\" in url:
        raise ValueError("Invalid destination URL")
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or parsed.hostname not in HOSTS
            or parsed.username is not None or parsed.password is not None
            or parsed.port is not None):
        raise ValueError("Handoff destination must use an allowed HTTPS host")
    return url


def single_url(text):
    """Read one URL, allowing a Markdown link or a terminal sentence period."""
    urls = list(dict.fromkeys(u.rstrip(".,;") for u in re.findall(r"https?://[^\s<>\])]+", text)))
    if len(urls) != 1:
        raise ValueError("Handoff needs one destination in target: or link:")
    return checked_url(urls[0])


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
        if sep and key.lower() in {"target", "link", "done-when"}:
            fields[key.lower()] = value.strip()
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


def run(argv, **kwargs):
    """Keep argument boundaries intact and bound external commands."""
    return subprocess.run([str(a) for a in argv], timeout=15, check=True, **kwargs)


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


def navigate_many(urls, terminal):
    """Open each URL and apply the layout dictated by the first two destinations."""
    env = dict(os.environ, LAYOUT_ALACRITTY_WINDOW=terminal)
    primary = urls[:2]
    slack = [u for u in primary if urlsplit(u).hostname in SLACK_HOSTS | {"app.slack.com"}]
    browsers = [u for u in primary if u not in slack]
    browser_count = 0
    browser_windows = []
    for index, url in enumerate(urls):
        if urlsplit(url).hostname in SLACK_HOSTS | {"app.slack.com"}:
            run(["xdg-open", slack_deep_link(url)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            continue
        browser_count += 1
        browser = os.environ.get("HANDOFF_BROWSER_COMMAND")
        new_window = not slack and len(browsers) >= 2 and browser_count == 2
        try:
            if not browser or new_window:
                raise OSError("Chrome window required")
            run([browser, url])
        except (OSError, subprocess.SubprocessError):
            args = [os.environ.get("HANDOFF_CHROME_COMMAND", "google-chrome-stable")]
            if new_window:
                args.append("--new-window")
            subprocess.Popen(args + [url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        time.sleep(0.5)
        if index < 2:
            browser_windows.append(window_id("google-chrome"))
    if not urls:
        return
    if browser_windows:
        env["LAYOUT_BROWSER_WINDOW"] = browser_windows[0]
    if len(browser_windows) > 1:
        env["LAYOUT_BROWSER_WINDOW_2"] = browser_windows[1]
    layout = "10" if slack and browsers else "8" if slack else "7" if len(browsers) >= 2 else "2"
    run([os.environ.get("HANDOFF_LAYOUT_COMMAND", str(ROOT / "__layouts.sh")), layout],
        env=env, stdout=subprocess.DEVNULL)


def agent_session(task):
    """Return the newest declared agent session without interpreting other notes."""
    fields = [a.get("description", "").partition(":")
              for a in sorted(task.get("annotations", []), key=lambda a: a.get("entry", ""))]
    values = [value.strip() for key, sep, value in fields
              if sep and key.strip().lower() == "agent"]
    return values[-1] if values else ""


def annotation_urls(task):
    """Return the latest target and every explicit link note in task order."""
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
        match = re.match(r"^\s*link:\s*(.*)$", annotation.get("description", ""), re.I)
        if match:
            try:
                urls.append(single_url(match.group(1)))
            except ValueError as error:
                print(f"Could not open handoff destination: {error}", file=sys.stderr)
    return list(dict.fromkeys(url for url in urls if url))


KINDS = {"slack", "command", "pr", "ack", "other"}
# Typed into the new window; it names the variable, never the task text, so
# nothing from the row is parsed by the shell. Enter submits only this builtin
# line: print -z leaves the command at the next prompt, unsubmitted.
PREFILL = ' print -rz -- "$HANDOFF_CMD"; unset HANDOFF_CMD; clear'


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


def open_command_window(uuid, command):
    """Open a tmux window named after the row whose prompt holds command."""
    if not command:
        raise ValueError("command handoff has no cmd: note; add one with __tw.sh note <ref> 'cmd: <command>'")
    if any(ord(char) < 32 or ord(char) == 127 for char in command):
        raise ValueError("cmd: note must be one line without control characters")
    pane = os.environ.get("TMUX_PANE", "")
    if not re.fullmatch(r"%[0-9]+", pane):
        raise ValueError("no tmux pane to open the command beside; press s in the handoffs view")
    tmux = os.environ.get("HANDOFF_TMUX_COMMAND", "tmux")
    session = run([tmux, "display-message", "-p", "-t", pane, "#{session_id}"],
                  capture_output=True, text=True).stdout.strip()
    if not re.fullmatch(r"\$[0-9]+", session):
        raise ValueError("could not resolve the tmux session of " + pane)
    # The command travels as one argv element into the window's environment.
    window = run([tmux, "new-window", "-P", "-F", "#{pane_id}", "-t", session + ":",
                  "-n", uuid[:8], "-e", "HANDOFF_CMD=" + command, "--", "zsh", "-i"],
                 capture_output=True, text=True).stdout.strip()
    if not re.fullmatch(r"%[0-9]+", window):
        raise ValueError("tmux did not report the new window's pane")
    run([tmux, "send-keys", "-t", window, "-l", PREFILL])
    run([tmux, "send-keys", "-t", window, "Enter"])
    return window


def act_on_kind(task):
    """Run the action s means for this kind after the links open.

    command opens a terminal with the cmd: note at the prompt; slack copies the
    newest draft: note; pr, ack and other only open what they opened before.
    Returns the kind. A failed action is reported.
    """
    kind = task_kind(task)
    try:
        if kind == "command":
            open_command_window(task["uuid"], newest_note(task, "cmd"))
        elif kind == "slack":
            draft = newest_note(task, "draft")
            if draft and not copy_to_clipboard(draft):
                print("Could not copy the draft: install xclip or wl-copy, then press s again.",
                      file=sys.stderr)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Handoff {kind} action: {error}", file=sys.stderr)
    return kind


def switch_agent_session(session):
    """Switch the current tmux client to an existing exact session name."""
    if not session or any(ord(char) < 32 or ord(char) == 127 for char in session):
        return False
    tmux = os.environ.get("HANDOFF_TMUX_COMMAND", "tmux")
    target = "=" + session
    try:
        exists = subprocess.run([tmux, "has-session", "-t", target], timeout=5,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if exists.returncode != 0:
            return False
        run([tmux, "switch-client", "-t", target], stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL)
        return True
    except (OSError, subprocess.SubprocessError):
        return False


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
    mode = args.pop(0) if args and args[0] in {"start", "stop"} else "start"
    if not args or not UUID.fullmatch(args[0]):
        print("Select a handoff using its full task UUID.", file=sys.stderr)
        return 2
    uuid = args[0]
    task_bin = os.environ.get("HANDOFF_TASK_COMMAND", "task")
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
        if old and old.get("uuid") != uuid and old.get("pane") != pane:
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
            kind = act_on_kind(task)
            # Switching to an agent session would hide the command window.
            if kind != "command":
                switch_agent_session(agent_session(task))
        finally:
            run([floater, "pin", uuid, pane])
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Handoff navigation: {error}", file=sys.stderr)
        sys.exit(1)
