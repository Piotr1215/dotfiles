#!/usr/bin/env python3
# PROJECT: github-notifications
"""Preview or mark closed and merged pull-request notifications Done.

Uses the existing gh login. Preview is the default; --apply enables writes.
Run through __cron_run.sh for the local cron dashboard and audit log.
"""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


NOTIFICATIONS = "/notifications?all=true&per_page=50"
PR_URL = re.compile(r"https://api\.github\.com(/repos/[^/?#]+/[^/?#]+/pulls/[0-9]+)\Z")


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


def cleanup(api, apply=False, output=print, receipts=None, on_done=None):
    """Plan with GETs, then recheck each eligible thread and PR before DELETE."""
    receipts = receipts if receipts is not None else {}
    counts = dict(scanned=0, candidates=0, done=0, kept=0, skipped=0, errors=0)
    candidates = []
    pull_requests = {}
    mode = "apply" if apply else "preview"
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
                if not isinstance(pr, dict) or pr.get("state") not in ("open", "closed"):
                    raise APIError("Unknown PR state; retain the thread and retry")
                if pr["state"] == "open":
                    counts["kept"] += 1
                    continue
                counts["candidates"] += 1
                candidates.append((identifier, updated, endpoint, subject))
                output(f"CANDIDATE: thread={identifier} pr={endpoint} state=closed")
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
                    if not isinstance(pr, dict) or pr.get("state") not in ("open", "closed"):
                        raise APIError("Unknown PR state during recheck; retain it and retry")
                    if pr["state"] != "closed":
                        counts["kept"] += 1
                        output(f"KEEP: thread={identifier} PR reopened")
                        continue
                    api("DELETE", thread_path)
                    counts["done"] += 1
                    receipts[identifier] = updated
                    output(f"DONE: thread={identifier} pr={endpoint}")
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
        return cleanup(github_api, apply=args.apply, receipts=receipts,
                       on_done=lambda value: save_receipts(args.state_file, value))
    except (OSError, ValueError):
        print("ERROR: cannot read or lock Done receipts; check the state file before retrying")
        print(f"SUMMARY: mode={'apply' if args.apply else 'preview'} scanned=0 candidates=0 done=0 kept=0 skipped=0 errors=1")
        return 1
    finally:
        if lock is not None:
            lock.close()


if __name__ == "__main__":
    raise SystemExit(main())
