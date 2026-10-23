#!/usr/bin/env python3
# PROJECT: github-notifications
"""Preview or mark closed and unrequested bot pull-request notifications Done,
and record every notification event for Kendra.

Uses the existing gh login. Preview is the default; --apply enables writes.
Run through __cron_run.sh for the local cron dashboard and audit log.

Recording (--apply, off with --no-record): every thread whose updated_at is new
since the last run becomes one `github` record in notifications.log, before any
thread is marked Done, so notify-watch hands it to Kendra:

  <date time>\tgithub\t🐙<actor> on <repo>#<n>:\tkind:<reason> type:<subject type>
  who:<self|other|bot|-> thread:<id> at:<updated_at> link:<url> | <what> · <title>

The actor and text come from the thread's latest comment (at most
FETCH_LIMIT reads a run; past that, or on a failed read, the record carries
the title only). pr-watch already DMs movement on the PRs it watches and
direct review requests, so a PR thread whose URL is a key of its state file
(~/.claude/data/pr-watermarks.json), or in its _reviewRequests, is marked
recorded without a record. An unreadable state file records everything:
a duplicate beats a drop. The first run (no recorded file) records only the
last FIRST_HOURS hours and seeds the rest. recorded.json, beside done.json,
maps thread id to the updated_at last recorded.
"""

import argparse
import fcntl
import json
import os
import re
import subprocess
import tempfile
import time
from datetime import UTC, datetime
from pathlib import Path

NOTIFICATIONS = "/notifications?all=true&per_page=50"
PR_URL = re.compile(r"https://api\.github\.com(/repos/[^/?#]+/[^/?#]+/pulls/[0-9]+)\Z")
BOT_LOGINS = {"renovate", "renovate[bot]", "dependabot", "dependabot[bot]",
              "loft-bot", "vcluster-bot-approver"}
PERSONAL_REASONS = {"mention", "team_mention", "assign"}
API_ROOT = "https://api.github.com"
FETCH_LIMIT = 15
FIRST_HOURS = 2
MAX_TEXT = 400
MAX_TITLE = 100


class APIError(Exception):
    """An API failure whose optional HTTP status can identify a stale thread."""

    def __init__(self, message, status=None):
        super().__init__(message)
        self.status = status


def github_api(method, endpoint, paginate=False):
    """Call gh without a shell or printing credentials or response bodies."""
    command = ["gh", "api", "--hostname", "github.com", "--method", method, endpoint]
    if paginate:
        command += ["--paginate", "--slurp"]
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise APIError("gh could not complete the request; check gh and connectivity") from exc
    if result.returncode:
        match = re.search(r"HTTP ([0-9]{3})", result.stderr)
        status = int(match.group(1)) if match else None
        raise APIError("GitHub request failed; check gh authentication and API access", status)
    try:
        return json.loads(result.stdout) if result.stdout.strip() else None
    except json.JSONDecodeError as exc:
        raise APIError("GitHub returned invalid JSON; retry the run") from exc


def is_bot_pr(pr):
    """Use GitHub's author type and explicit service accounts, never the title."""
    author = pr.get("user")
    return (isinstance(author, dict)
            and (author.get("type") == "Bot"
                 or str(author.get("login", "")).casefold() in BOT_LOGINS))


def matching_rule(thread, pr, get_viewer):
    """Closed PRs always qualify; open bot PRs qualify without a personal target."""
    if not isinstance(pr, dict) or pr.get("state") not in ("open", "closed"):
        raise APIError("Unknown PR state; retain the thread and retry")
    if pr["state"] == "closed":
        return "closed"
    if not is_bot_pr(pr):
        return None
    reason = thread.get("reason")
    if not isinstance(reason, str):
        raise APIError("Unknown notification reason; retain it and retry")
    if reason in PERSONAL_REASONS:
        return None
    viewer = get_viewer().casefold()
    for field in ("requested_reviewers", "assignees"):
        people = pr.get(field)
        if not isinstance(people, list) or any(
                not isinstance(person, dict) or not isinstance(person.get("login"), str)
                for person in people):
            raise APIError("Cannot confirm personal review or assignment; retain it and retry")
        if any(person["login"].casefold() == viewer for person in people):
            return None
    if "body" not in pr or (pr["body"] is not None and not isinstance(pr["body"], str)):
        raise APIError("Cannot confirm personal mentions; retain it and retry")
    if re.search(r"(?<![\w-])@" + re.escape(viewer) + r"(?![\w-])", pr["body"] or "", re.I):
        return None
    return "bot"


def one_line(text, limit):
    text = re.sub(r"\s+", " ", text or "").strip()
    return text if len(text) <= limit else text[:limit - 3] + "..."


def html_url(api_url, repo):
    """The github.com page for a notification subject's API URL."""
    m = re.fullmatch(r"https://api\.github\.com/repos/([^/]+/[^/]+)/(pulls|issues)/([0-9]+)", api_url or "")
    if m:
        return f"https://github.com/{m.group(1)}/{'pull' if m.group(2) == 'pulls' else 'issues'}/{m.group(3)}"
    if re.fullmatch(r"https://api\.github\.com/repos/[^/]+/[^/]+/releases/[0-9]+", api_url or ""):
        return f"https://github.com/{repo}/releases"
    return f"https://github.com/{repo}" if repo else "https://github.com/notifications"


def epoch_of(stamp):
    return datetime.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=UTC).timestamp()


class Recorder:
    """Appends one `github` record per new notification event to the log.

    recorded maps thread id to the updated_at last recorded. watched holds the
    PR URLs pr-watch reports on, direct the PRs it reports as direct review
    requests. first_since (epoch) seeds older threads silently on a first run.
    write=False prints the records instead (preview)."""

    def __init__(self, api, log, recorded, watched, direct, get_viewer=None, first_since=None,
                 write=True, output=print, now=None):
        self.api, self.log, self.recorded = api, Path(log), recorded
        self.watched, self.direct = watched, direct
        self.get_viewer, self.first_since = get_viewer, first_since
        self.write, self.output = write, output
        self.now = now if now is not None else time.time()
        self.fetched = 0
        self.failed = False
        self.counts = {"recorded": 0, "covered": 0, "bot_quiet": 0, "seeded": 0}

    def __call__(self, thread, pr=None, rule=None):
        """One thread; for a pull request, pr and the cleanup rule it matched."""
        identifier, updated = thread["id"], thread.get("updated_at")
        if not isinstance(updated, str) or self.recorded.get(identifier) == updated:
            return
        subject = thread["subject"]
        repo = (thread.get("repository") or {}).get("full_name") or ""
        link = html_url(subject.get("url"), repo)
        if self.first_since is not None and epoch_of(updated) < self.first_since:
            self.counts["seeded"] += 1
        elif link in self.watched or (thread.get("reason") == "review_requested" and link in self.direct):
            self.counts["covered"] += 1
        elif rule == "bot":
            # An open bot PR nobody asked Piotr about: the cleanup marks it Done as noise.
            self.counts["bot_quiet"] += 1
        else:
            self._append(self._line(thread, subject, repo, link, pr))
            self.counts["recorded"] += 1
        self.recorded[identifier] = updated

    def _get(self, endpoint):
        if self.fetched >= FETCH_LIMIT:
            return None
        self.fetched += 1
        try:
            return self.api("GET", endpoint)
        except APIError:
            self.output("WARN: cannot read a thread's latest comment; the record carries the title only")
            return None

    def _comment(self, thread, subject, repo):
        """The comment that moved the thread, or None: latest_comment_url when
        GitHub fills it, else the issue's newest comment updated in the last 15
        minutes before the thread (GitHub leaves it null on pull requests)."""
        url = subject.get("latest_comment_url")
        if isinstance(url, str) and url.startswith(API_ROOT) and url != subject.get("url"):
            got = self._get(url[len(API_ROOT):])
            return got if isinstance(got, dict) else None
        number = (subject.get("url") or "").rsplit("/", 1)[-1]
        if subject.get("type") not in ("PullRequest", "Issue") or not number.isdigit() or not repo:
            return None
        since = datetime.fromtimestamp(epoch_of(thread["updated_at"]) - 900, UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
        got = self._get(f"/repos/{repo}/issues/{number}/comments?since={since}&per_page=100")
        return got[-1] if isinstance(got, list) and got and isinstance(got[-1], dict) else None

    def _who(self, user):
        if not isinstance(user, dict) or not user.get("login"):
            return "-"
        if user.get("type") == "Bot" or str(user["login"]).casefold() in BOT_LOGINS:
            return "bot"
        try:
            viewer = self.get_viewer() if self.get_viewer else ""
        except APIError:
            viewer = ""
        return "self" if viewer and user["login"].casefold() == viewer.casefold() else "other"

    def _line(self, thread, subject, repo, link, pr):
        url = subject.get("url") or ""
        number = url.rsplit("/", 1)[-1]
        where = f"{repo}#{number}" if number.isdigit() and "/releases/" not in url else repo or "github"
        comment = self._comment(thread, subject, repo)
        if comment and comment.get("body"):
            user, what = comment.get("user"), "commented: " + one_line(comment["body"], MAX_TEXT)
            link = comment.get("html_url") or link
        elif isinstance(pr, dict) and pr.get("state") == "closed":
            user = pr.get("merged_by") if pr.get("merged") else None
            what = "merged" if pr.get("merged") else "closed"
        else:
            user, what = None, f"{subject.get('type') or 'thread'} {thread.get('reason') or 'updated'}"
        who = self._who(user)
        head = f"🐙{user['login']} on {where}:" if who != "-" else f"🐙{where}:"
        stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(self.now))
        meta = (f"kind:{thread.get('reason') or '-'} type:{subject.get('type') or '-'} who:{who} "
                f"thread:{thread['id']} at:{thread['updated_at'][:19]}Z link:{link}")
        return f"{stamp}\tgithub\t{one_line(head, 120)}\t{meta} | {what} · {one_line(subject.get('title'), MAX_TITLE)}\n"

    def _append(self, line):
        if not self.write:
            self.output("RECORD: " + line.rstrip("\n"))
            return
        self.log.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(self.log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(fd, line.encode())
        finally:
            os.close(fd)


def pr_watch_sets(path):
    """The PR URLs pr-watch watches and its direct review requests; empty sets
    when its state file is unreadable, so everything is recorded."""
    try:
        state = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return set(), set()
    if not isinstance(state, dict):
        return set(), set()
    direct = state.get("_reviewRequests")
    return ({k for k in state if k.startswith("https://github.com/")},
            set(direct) if isinstance(direct, list) else set())


def cleanup(api, apply=False, output=print, receipts=None, on_done=None, recorder=None):
    """Plan with GETs, then recheck each eligible thread and PR before DELETE."""
    receipts = receipts if receipts is not None else {}
    counts = dict(scanned=0, candidates=0, done=0, kept=0, skipped=0, errors=0,
                  closed_done=0, bot_done=0, personal_kept=0)
    candidates = []
    pull_requests = {}
    identity = {}
    mode = "apply" if apply else "preview"

    def get_viewer():
        """Resolve identity once; a failure must not make a bot thread eligible."""
        if "error" in identity:
            raise identity["error"]
        if "login" not in identity:
            try:
                user = api("GET", "/user")
                if not isinstance(user, dict) or not isinstance(user.get("login"), str) or not user["login"]:
                    raise APIError("Cannot identify the signed-in user; retain bot threads and check gh login")
                identity["login"] = user["login"]
            except APIError as exc:
                identity["error"] = exc
                raise
        return identity["login"]

    started = recorder
    if recorder is not None and recorder.get_viewer is None:
        recorder.get_viewer = get_viewer

    def record(rec, *args):
        """Runs the recorder; a log it cannot append to stops recording."""
        if rec is None:
            return None
        try:
            rec(*args)
            return rec
        except OSError:
            counts["errors"] += 1
            output("ERROR: cannot append to notifications.log; recording stops, the next run retries")
            rec.failed = True
            return None
    try:
        pages = api("GET", NOTIFICATIONS, paginate=True)
        if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
            raise APIError("Unexpected notification response; retain everything and retry")
        seen = set()
        for thread in (item for page in pages for item in page):
            counts["scanned"] += 1
            try:
                if not isinstance(thread, dict):
                    raise APIError("Malformed notification; retain it and retry")
                identifier = thread.get("id")
                subject = thread.get("subject")
                if not isinstance(identifier, str) or not re.fullmatch(r"[0-9]+", identifier):
                    raise APIError("Malformed thread ID; retain it and retry")
                if not isinstance(subject, dict):
                    raise APIError("Missing notification subject; retain it and retry")
                if identifier in seen:
                    counts["skipped"] += 1
                    continue
                seen.add(identifier)
                if subject.get("type") != "PullRequest":
                    recorder = record(recorder, thread)
                    counts["kept"] += 1
                    continue
                updated = thread.get("updated_at")
                url = subject.get("url")
                match = PR_URL.fullmatch(url) if isinstance(url, str) else None
                if not match or not isinstance(updated, str) or not updated:
                    raise APIError("Missing PR URL or timestamp; retain it and retry")
                # all=true also returns Done threads. A receipt avoids replaying
                # them until a new event changes the notification timestamp.
                if receipts.get(identifier) == updated:
                    counts["skipped"] += 1
                    continue
                endpoint = match.group(1)
                if endpoint not in pull_requests:
                    pull_requests[endpoint] = api("GET", endpoint)
                pr = pull_requests[endpoint]
                rule = matching_rule(thread, pr, get_viewer)
                recorder = record(recorder, thread, pr, rule)
                if rule is None:
                    counts["kept"] += 1
                    if is_bot_pr(pr):
                        counts["personal_kept"] += 1
                        output(f"KEEP: thread={identifier} personally targeted bot PR")
                    continue
                counts["candidates"] += 1
                candidates.append((identifier, updated, endpoint, subject))
                output(f"CANDIDATE: thread={identifier} pr={endpoint} rule={rule}")
            except APIError as exc:
                if exc.status == 404:
                    counts["skipped"] += 1
                    output("WARN: PR no longer available; retain the thread and restore access before retrying")
                else:
                    counts["errors"] += 1
                    output(f"WARN: {exc}")

        if apply:
            for identifier, updated, endpoint, subject in candidates:
                try:
                    thread_path = f"/notifications/threads/{identifier}"
                    current = api("GET", thread_path)
                    if not isinstance(current, dict):
                        raise APIError("Unknown thread state; retain it and retry")
                    if (current.get("id") != identifier
                            or current.get("updated_at") != updated
                            or current.get("subject") != subject):
                        counts["skipped"] += 1
                        output(f"SKIP: thread={identifier} changed; reconsider next run")
                        continue
                    pr = api("GET", endpoint)
                    rule = matching_rule(current, pr, get_viewer)
                    if rule is None:
                        counts["kept"] += 1
                        if is_bot_pr(pr):
                            counts["personal_kept"] += 1
                        output(f"KEEP: thread={identifier} current rules no longer match")
                        continue
                    api("DELETE", thread_path)
                    counts["done"] += 1
                    counts[rule + "_done"] += 1
                    receipts[identifier] = updated
                    output(f"DONE: thread={identifier} pr={endpoint} rule={rule}")
                    if on_done is not None:
                        on_done(receipts)
                except APIError as exc:
                    if exc.status == 404:
                        counts["skipped"] += 1
                        output(f"SKIP: thread={identifier} no longer available")
                    else:
                        counts["errors"] += 1
                        output(f"WARN: thread={identifier}: {exc}")
                except OSError:
                    counts["errors"] += 1
                    output("ERROR: cannot save Done receipts; check state directory permissions")
                    break
    except APIError as exc:
        counts["errors"] += 1
        output(f"ERROR: {exc}")
    finally:
        if started is not None:
            counts.update(started.counts)
        output("SUMMARY: mode=" + mode + " " + " ".join(f"{k}={v}" for k, v in counts.items()))
    return 1 if counts["errors"] else 0


def save_receipts(path, receipts):
    """Replace the receipt file atomically without losing earlier successes."""
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as handle:
            json.dump(receipts, handle, sort_keys=True)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main(argv=None):
    """Load receipts; serialize apply runs while leaving preview read only."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="mark matching threads Done")
    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    parser.add_argument("--state-file", type=Path, default=state_home / "github-notifications/done.json")
    parser.add_argument("--no-record", action="store_true", help="write no notifications.log records")
    parser.add_argument("--log", type=Path, default=Path(
        os.environ.get("GITHUB_NOTIFY_LOG") or os.environ.get("NOTIFY_LOG")
        or Path.home() / ".local/state/notifications.log"))
    parser.add_argument("--pr-watch-state", type=Path, default=Path(os.environ.get(
        "GITHUB_NOTIFY_PR_WATCH", Path.home() / ".claude/data/pr-watermarks.json")))
    args = parser.parse_args(argv)
    lock = None
    try:
        if args.apply:
            args.state_file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            lock = args.state_file.with_suffix(".lock").open("a")
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                print("SUMMARY: mode=apply scanned=0 candidates=0 done=0 kept=0 skipped=1 errors=0 lock=busy")
                return 0
        try:
            receipts = json.loads(args.state_file.read_text())
        except FileNotFoundError:
            receipts = {}
        if not isinstance(receipts, dict) or any(not isinstance(k, str) or not isinstance(v, str) for k, v in receipts.items()):
            raise ValueError("invalid receipt format")
        recorder = None
        recorded_file = args.state_file.with_name("recorded.json")
        if not args.no_record:
            try:
                recorded = json.loads(recorded_file.read_text())
                first_since = None
            except FileNotFoundError:
                recorded, first_since = {}, time.time() - FIRST_HOURS * 3600
            if not isinstance(recorded, dict):
                raise ValueError("invalid recorded format")
            watched, direct = pr_watch_sets(args.pr_watch_state)
            recorder = Recorder(github_api, args.log, recorded, watched, direct,
                                first_since=first_since, write=args.apply)
        code = cleanup(github_api, apply=args.apply, receipts=receipts,
                       on_done=lambda value: save_receipts(args.state_file, value), recorder=recorder)
        if recorder is not None and args.apply:
            save_receipts(recorded_file, recorder.recorded)
        return code
    except (OSError, ValueError):
        print("ERROR: cannot read or lock Done receipts; check the state file before retrying")
        print(f"SUMMARY: mode={'apply' if args.apply else 'preview'} scanned=0 candidates=0 done=0 kept=0 skipped=0 errors=1")
        return 1
    finally:
        if lock is not None:
            lock.close()


if __name__ == "__main__":
    raise SystemExit(main())
