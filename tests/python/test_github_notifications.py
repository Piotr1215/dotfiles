"""Offline behavior tests for GitHub notification cleanup."""

import copy
import contextlib
import fcntl
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).parents[2] / "scripts" / "__github_notifications.py"
LIST = "/notifications?all=true&per_page=50"
PR = "/repos/example/project/pulls/123"


def load_module():
    spec = importlib.util.spec_from_file_location("github_notifications", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def notification(identifier="1", **changes):
    value = {
        "id": identifier,
        "updated_at": "2026-10-22T08:00:00Z",
        "reason": "subscribed",
        "subject": {"type": "PullRequest", "url": "https://api.github.com" + PR},
    }
    value.update(changes)
    return value


def pull(state="closed", merged=False):
    return {"state": state, "merged": merged}


class ScriptedAPI:
    """Reject unexpected calls, including writes during preview."""

    def __init__(self, steps):
        self.steps = list(steps)
        self.calls = []

    def __call__(self, method, endpoint, paginate=False):
        call = (method, endpoint, paginate)
        self.calls.append(call)
        if not self.steps:
            raise AssertionError(f"Unexpected API call: {call}")
        expected, result = self.steps.pop(0)
        if call != expected:
            raise AssertionError(f"Expected {expected}, got {call}")
        if isinstance(result, Exception):
            raise result
        return copy.deepcopy(result)


def get(endpoint, result, paginate=False):
    return (("GET", endpoint, paginate), result)


def delete(identifier, result=None):
    return (("DELETE", f"/notifications/threads/{identifier}", False), result)


class CleanupTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def run_cleanup(self, steps, apply=False, expected_status=0):
        api = ScriptedAPI(steps)
        lines = []
        status = self.module.cleanup(api, apply=apply, output=lines.append)
        self.assertEqual(status, expected_status, lines)
        self.assertFalse(api.steps, f"Unconsumed API steps: {api.steps}")
        self.assertTrue(lines, "Missing final summary")
        self.assertTrue(lines[-1].startswith("SUMMARY:"), lines)
        for field in ("mode", "scanned", "candidates", "done", "kept", "skipped", "errors"):
            self.assertIn(field, lines[-1])
        return api, lines

    def test_preview_is_default_and_never_deletes(self):
        api, _ = self.run_cleanup([
            get(LIST, [[notification()]], paginate=True), get(PR, pull()),
        ])
        self.assertTrue(all(call[0] == "GET" for call in api.calls))

    def test_closed_merged_and_unmerged_are_deleted(self):
        for merged in (False, True):
            with self.subTest(merged=merged):
                item = notification()
                api, _ = self.run_cleanup([
                    get(LIST, [[item]], paginate=True), get(PR, pull(merged=merged)),
                    get("/notifications/threads/1", item), get(PR, pull(merged=merged)),
                    delete("1"),
                ], apply=True)
                self.assertEqual(api.calls[-3:], [
                    ("GET", "/notifications/threads/1", False),
                    ("GET", PR, False), ("DELETE", "/notifications/threads/1", False),
                ])

    def test_open_pull_requests_are_retained(self):
        self.run_cleanup([
            get(LIST, [[notification()]], paginate=True), get(PR, pull(state="open")),
        ], apply=True)

    def test_issues_and_releases_are_retained(self):
        for kind in ("Issue", "Release"):
            with self.subTest(kind=kind):
                item = notification(subject={
                    "type": kind, "url": "https://api.github.com/repos/example/project/issues/123",
                })
                self.run_cleanup([get(LIST, [[item]], paginate=True)], apply=True)

    def test_reason_and_author_do_not_protect_closed_pull_requests(self):
        for reason in ("mention", "author"):
            with self.subTest(reason=reason):
                item = notification(reason=reason)
                self.run_cleanup([
                    get(LIST, [[item]], paginate=True), get(PR, pull()),
                    get("/notifications/threads/1", item), get(PR, pull()), delete("1"),
                ], apply=True)

    def test_changed_notification_is_skipped(self):
        self.run_cleanup([
            get(LIST, [[notification()]], paginate=True), get(PR, pull()),
            get("/notifications/threads/1", notification(updated_at="2026-10-22T09:00:00Z")),
        ], apply=True)

    def test_reopened_pull_request_is_skipped(self):
        self.run_cleanup([
            get(LIST, [[notification()]], paginate=True), get(PR, pull()),
            get("/notifications/threads/1", notification()), get(PR, pull(state="open")),
        ], apply=True)

    def test_deleted_thread_is_a_successful_skip(self):
        self.run_cleanup([
            get(LIST, [[notification()]], paginate=True), get(PR, pull()),
            get("/notifications/threads/1", self.module.APIError("Not found", status=404)),
        ], apply=True)

    def test_all_pages_are_scanned_and_planning_reads_are_cached(self):
        self.run_cleanup([
            get(LIST, [[notification("1")], [notification("2")]], paginate=True), get(PR, pull()),
        ])

    def test_apply_rechecks_cached_pull_request_for_each_thread(self):
        first, second = notification("1"), notification("2")
        self.run_cleanup([
            get(LIST, [[first], [second]], paginate=True), get(PR, pull()),
            get("/notifications/threads/1", first), get(PR, pull()), delete("1"),
            get("/notifications/threads/2", second), get(PR, pull(state="open")),
        ], apply=True)

    def test_empty_notifications_still_print_summary(self):
        self.run_cleanup([get(LIST, [], paginate=True)])

    def test_list_failure_returns_error_and_prints_summary(self):
        self.run_cleanup([
            get(LIST, self.module.APIError("Unavailable", status=503), paginate=True),
        ], expected_status=1)

    def test_pull_request_failure_fails_closed(self):
        self.run_cleanup([
            get(LIST, [[notification()]], paginate=True),
            get(PR, self.module.APIError("Forbidden", status=403)),
        ], apply=True, expected_status=1)

    def test_missing_pull_request_is_retained_without_error(self):
        self.run_cleanup([
            get(LIST, [[notification()]], paginate=True),
            get(PR, self.module.APIError("Not found", status=404)),
        ], apply=True)

    def test_thread_recheck_failure_fails_closed(self):
        self.run_cleanup([
            get(LIST, [[notification()]], paginate=True), get(PR, pull()),
            get("/notifications/threads/1", self.module.APIError("Unavailable", status=503)),
        ], apply=True, expected_status=1)

    def test_pull_request_recheck_failure_fails_closed(self):
        self.run_cleanup([
            get(LIST, [[notification()]], paginate=True), get(PR, pull()),
            get("/notifications/threads/1", notification()),
            get(PR, self.module.APIError("Unavailable", status=503)),
        ], apply=True, expected_status=1)

    def test_delete_failure_is_reported_as_error(self):
        _, lines = self.run_cleanup([
            get(LIST, [[notification()]], paginate=True), get(PR, pull()),
            get("/notifications/threads/1", notification()), get(PR, pull()),
            delete("1", self.module.APIError("Forbidden", status=403)),
        ], apply=True, expected_status=1)
        self.assertRegex(lines[-1], r"\bdone\s*[=:]\s*0\b")
        self.assertRegex(lines[-1], r"\berrors\s*[=:]\s*[1-9]\d*\b")

    def test_unknown_pull_request_state_is_retained_and_reported(self):
        for metadata in ({}, {"state": "unknown"}, None):
            with self.subTest(metadata=metadata):
                api = ScriptedAPI([get(LIST, [[notification()]], paginate=True), get(PR, metadata)])
                lines = []
                status = self.module.cleanup(api, apply=True, output=lines.append)
                self.assertEqual(status, 1)
                self.assertFalse(api.steps)
                self.assertTrue(all(call[0] == "GET" for call in api.calls))
                self.assertTrue(lines[-1].startswith("SUMMARY:"), lines)
                self.assertGreater(len(lines), 1)

    def test_malformed_notifications_never_become_delete_targets(self):
        bad_items = [
            notification(identifier="not-a-number"), notification(subject=None),
            notification(subject={"type": "PullRequest", "url": "https://untrusted.example" + PR}),
            notification(subject={"type": "PullRequest", "url": "https://api.github.com/repos/example/project/issues/123"}),
        ]
        for item in bad_items:
            with self.subTest(item=item):
                api = ScriptedAPI([get(LIST, [[item]], paginate=True)])
                lines = []
                self.assertEqual(self.module.cleanup(api, apply=True, output=lines.append), 1)
                self.assertFalse(api.steps)
                self.assertTrue(lines[-1].startswith("SUMMARY:"), lines)
                self.assertGreater(len(lines), 1)


class ReceiptTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def test_unchanged_receipt_skips_before_pr_lookup(self):
        item = notification()
        receipts = {"1": item["updated_at"]}
        api = ScriptedAPI([get(LIST, [[item]], paginate=True)])
        lines = []
        self.assertEqual(self.module.cleanup(api, apply=True, receipts=receipts, output=lines.append), 0)
        self.assertFalse(api.steps)
        self.assertIn("skipped=1", lines[-1])

    def test_preview_preserves_receipts_and_never_saves(self):
        receipts = {"1": "older"}
        callback = mock.Mock()
        api = ScriptedAPI([get(LIST, [[notification()]], paginate=True), get(PR, pull())])
        self.assertEqual(self.module.cleanup(api, receipts=receipts, on_done=callback, output=lambda _: None), 0)
        self.assertEqual(receipts, {"1": "older"})
        callback.assert_not_called()
        self.assertFalse(api.steps)

    def test_changed_timestamp_is_deleted_and_receipted(self):
        item = notification()
        receipts = {"1": "older", "2": "preserve"}
        saved = []
        api = ScriptedAPI([
            get(LIST, [[item]], paginate=True), get(PR, pull()),
            get("/notifications/threads/1", item), get(PR, pull()), delete("1"),
        ])
        self.assertEqual(self.module.cleanup(api, apply=True, receipts=receipts,
                         on_done=lambda value: saved.append(dict(value)), output=lambda _: None), 0)
        self.assertEqual(receipts, {"1": item["updated_at"], "2": "preserve"})
        self.assertEqual(saved, [receipts])
        self.assertFalse(api.steps)

    def test_save_failure_reports_completed_delete_and_stops(self):
        first, second = notification("1"), notification("2")
        api = ScriptedAPI([
            get(LIST, [[first, second]], paginate=True), get(PR, pull()),
            get("/notifications/threads/1", first), get(PR, pull()), delete("1"),
        ])
        receipts, lines = {}, []
        callback = mock.Mock(side_effect=OSError("disk full"))
        self.assertEqual(self.module.cleanup(api, apply=True, receipts=receipts,
                         on_done=callback, output=lines.append), 1)
        self.assertFalse(api.steps)
        self.assertEqual(receipts, {"1": first["updated_at"]})
        self.assertIn("done=1", lines[-1])
        self.assertIn("errors=1", lines[-1])


class EntryPointTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def test_default_preview_creates_no_state_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "missing" / "done.json"
            api = ScriptedAPI([get(LIST, [], paginate=True)])
            with mock.patch.object(self.module, "github_api", api), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(self.module.main(["--state-file", str(state)]), 0)
            self.assertFalse(api.steps)
            self.assertFalse(state.parent.exists())

    def test_malformed_receipts_prevent_api_calls(self):
        for contents in ("{broken", "[]", '{"1": 123}'):
            with self.subTest(contents=contents), tempfile.TemporaryDirectory() as directory:
                state = Path(directory) / "done.json"
                state.write_text(contents)
                with mock.patch.object(self.module, "github_api") as api, contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(self.module.main(["--state-file", str(state)]), 1)
                api.assert_not_called()
                self.assertIn("errors=1", output.getvalue().splitlines()[-1])

    def test_overlapping_apply_skips_without_api_calls(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "done.json"
            with state.with_suffix(".lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with mock.patch.object(self.module, "github_api") as api, contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(self.module.main(["--apply", "--state-file", str(state)]), 0)
                api.assert_not_called()
                self.assertIn("lock=busy", output.getvalue())

    def test_api_adapter_requests_all_pages(self):
        result = mock.Mock(returncode=0, stdout="[[1], [2]]", stderr="")
        with mock.patch.object(self.module.subprocess, "run", return_value=result) as run:
            self.assertEqual(self.module.github_api("GET", LIST, paginate=True), [[1], [2]])
        command = run.call_args.args[0]
        self.assertEqual(command, ["gh", "api", "--hostname", "github.com", "--method", "GET", LIST, "--paginate", "--slurp"])
        self.assertFalse(run.call_args.kwargs.get("shell", False))

    def test_api_adapter_extracts_http_status(self):
        result = mock.Mock(returncode=1, stdout="", stderr="gh: Not Found (HTTP 404)")
        with mock.patch.object(self.module.subprocess, "run", return_value=result):
            with self.assertRaises(self.module.APIError) as caught:
                self.module.github_api("GET", "/notifications/threads/1")
        self.assertEqual(caught.exception.status, 404)

    def test_api_adapter_accepts_empty_delete_response(self):
        result = mock.Mock(returncode=0, stdout="", stderr="")
        with mock.patch.object(self.module.subprocess, "run", return_value=result):
            self.assertIsNone(self.module.github_api("DELETE", "/notifications/threads/1"))

    def test_api_adapter_rejects_invalid_json(self):
        result = mock.Mock(returncode=0, stdout="<html>failure</html>", stderr="")
        with mock.patch.object(self.module.subprocess, "run", return_value=result):
            with self.assertRaises(self.module.APIError):
                self.module.github_api("GET", LIST)

    def test_saved_receipts_survive_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "done.json"
            self.module.save_receipts(state, {"1": "2026-10-22T08:00:00Z"})
            self.assertEqual(json.loads(state.read_text()), {"1": "2026-10-22T08:00:00Z"})
            self.assertEqual(list(state.parent.iterdir()), [state])


class BotRuleTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def bot_pull(self, **changes):
        value = {
            "state": "open", "title": "chore(deps): bump example to 1.1", "body": "",
            "user": {"type": "Bot", "login": "example-dependency[bot]"},
            "requested_reviewers": [], "assignees": [],
        }
        value.update(changes)
        return value

    def exercise(self, pr, reason="subscribed", apply=True, refreshed_pr=None,
                 refreshed_reason=None, viewer=None, expected_done=False, expected_status=0):
        item = notification(reason=reason)
        current = copy.deepcopy(item)
        if refreshed_reason is not None:
            current["reason"] = refreshed_reason
        calls, lines = [], []
        pr_reads = 0

        def api(method, endpoint, paginate=False):
            nonlocal pr_reads
            calls.append((method, endpoint, paginate))
            if (method, endpoint) == ("GET", LIST):
                return [[copy.deepcopy(item)]]
            if (method, endpoint) == ("GET", PR):
                pr_reads += 1
                return copy.deepcopy(refreshed_pr if pr_reads > 1 and refreshed_pr is not None else pr)
            if (method, endpoint) == ("GET", "/user"):
                if isinstance(viewer, Exception):
                    raise viewer
                return copy.deepcopy(viewer if viewer is not None else {"login": "viewer"})
            if (method, endpoint) == ("GET", "/notifications/threads/1"):
                self.assertTrue(apply)
                return copy.deepcopy(current)
            if (method, endpoint) == ("DELETE", "/notifications/threads/1"):
                self.assertTrue(apply)
                self.assertTrue(expected_done, "Protected notification was deleted")
                return None
            self.fail(f"Unexpected API call: {(method, endpoint, paginate)}")

        status = self.module.cleanup(api, apply=apply, output=lines.append)
        self.assertEqual(status, expected_status, lines)
        self.assertTrue(lines[-1].startswith("SUMMARY:"), lines)
        self.assertEqual(sum(call[0] == "DELETE" for call in calls), int(expected_done), lines)
        self.assertIn(f"done={int(expected_done)}", lines[-1])
        if expected_done:
            self.assertEqual(calls[-3:], [
                ("GET", "/notifications/threads/1", False),
                ("GET", PR, False), ("DELETE", "/notifications/threads/1", False),
            ])
        return calls, lines

    def test_open_bot_pull_request_is_cleared(self):
        calls, lines = self.exercise(self.bot_pull(), expected_done=True)
        self.assertEqual(calls.count(("GET", "/user", False)), 1)
        self.assertIn("bot_done=1", lines[-1])

    def test_bot_rule_does_not_depend_on_title_or_labels(self):
        for title in ("docs: explain configuration", "fix: change authorization behavior"):
            with self.subTest(title=title):
                self.exercise(self.bot_pull(title=title), expected_done=True)

    def test_known_service_accounts_are_treated_as_bots(self):
        for login in ("renovate", "dependabot[bot]", "loft-bot", "vcluster-bot-approver"):
            with self.subTest(login=login):
                self.exercise(self.bot_pull(user={"type": "User", "login": login}), expected_done=True)

    def test_personal_notification_reasons_are_protected(self):
        for reason in ("mention", "team_mention", "assign"):
            with self.subTest(reason=reason):
                self.exercise(self.bot_pull(), reason=reason)

    def test_body_review_and_assignment_protect_viewer(self):
        for changes in (
            {"body": "Please check this, @viewer."},
            {"requested_reviewers": [{"login": "viewer"}]},
            {"assignees": [{"login": "viewer"}]},
            {"requested_reviewers": [{"login": "VIEWER"}]},
        ):
            with self.subTest(changes=changes):
                self.exercise(self.bot_pull(**changes))

    def test_other_users_and_longer_login_do_not_protect(self):
        self.exercise(self.bot_pull(body="Thanks @viewer-tools",
                      requested_reviewers=[{"login": "someone-else"}],
                      assignees=[{"login": "someone-else"}]), expected_done=True)

    def test_human_chore_and_security_fix_are_retained(self):
        for title in ("chore(deps): bump example to 1.1", "fix(deps): resolve a security advisory"):
            with self.subTest(title=title):
                calls, _ = self.exercise(self.bot_pull(title=title,
                    user={"type": "User", "login": "human-contributor"}))
                self.assertNotIn(("GET", "/user", False), calls)

    def test_new_personal_target_or_human_author_blocks_delete(self):
        for changes in (
            {"body": "Please review @viewer"},
            {"requested_reviewers": [{"login": "viewer"}]},
            {"assignees": [{"login": "viewer"}]},
            {"user": {"type": "User", "login": "human-contributor"}},
        ):
            with self.subTest(changes=changes):
                self.exercise(self.bot_pull(), refreshed_pr=self.bot_pull(**changes))

    def test_new_reason_blocks_delete_even_with_same_timestamp(self):
        for reason in ("mention", "team_mention", "assign"):
            with self.subTest(reason=reason):
                self.exercise(self.bot_pull(), refreshed_reason=reason)

    def test_preview_never_deletes_open_bot_notification(self):
        _, lines = self.exercise(self.bot_pull(), apply=False)
        self.assertIn("candidates=1", lines[-1])

    def test_unknown_viewer_fails_closed(self):
        for viewer in (self.module.APIError("Forbidden", status=403), {}, {"login": None}, {"login": ""}):
            with self.subTest(viewer=viewer):
                self.exercise(self.bot_pull(), viewer=viewer, expected_status=1)

    def test_missing_personal_target_metadata_fails_closed(self):
        for key in ("body", "requested_reviewers", "assignees"):
            with self.subTest(key=key):
                metadata = self.bot_pull()
                del metadata[key]
                self.exercise(metadata, expected_status=1)

    def test_closed_personally_tagged_pr_still_clears_without_viewer(self):
        calls, _ = self.exercise(self.bot_pull(state="closed", body="@viewer",
                    requested_reviewers=[{"login": "viewer"}]), reason="mention", expected_done=True)
        self.assertNotIn(("GET", "/user", False), calls)


RECORD_REPO = {"full_name": "example/project"}


class RecordTest(unittest.TestCase):
    """Every new notification event becomes one `github` record for Kendra,
    written before the cleanup marks its thread Done. Gap: on 23 Oct the cron
    marked Piotr's merged flows#135 Done at 14:37Z and nothing ever recorded it,
    while gh showed 22 live items and notifications.log held none."""

    ISSUE = "/repos/example/project/issues/7"
    COMMENT = "/repos/example/project/issues/comments/99"

    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.log = Path(self.dir.name) / "notifications.log"

    def recorder(self, api, recorded=None, watched=(), direct=(), first_since=None, write=True):
        return self.module.Recorder(api, self.log, {} if recorded is None else recorded,
                                    set(watched), set(direct), first_since=first_since,
                                    write=write, output=lambda _: None, now=0)

    def fake(self, responses, log_at_delete=None):
        calls = []

        def api(method, endpoint, paginate=False):
            calls.append((method, endpoint))
            if method == "DELETE":
                if log_at_delete is not None:
                    log_at_delete.append(self.log.read_text() if self.log.exists() else "")
                return None
            if endpoint not in responses:
                raise AssertionError(f"Unexpected API call: {(method, endpoint)}")
            value = responses[endpoint]
            if isinstance(value, Exception):
                raise value
            return copy.deepcopy(value)
        return api, calls

    def records(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def issue_thread(self, **changes):
        value = notification("5", reason="mention", repository=RECORD_REPO, subject={
            "type": "Issue", "title": "flaky e2e on main",
            "url": "https://api.github.com" + self.ISSUE,
            "latest_comment_url": "https://api.github.com" + self.COMMENT})
        value.update(changes)
        return value

    def test_issue_mention_records_the_comment_and_its_author(self):
        api, _ = self.fake({
            LIST: [[self.issue_thread()]], "/user": {"login": "viewer"},
            self.COMMENT: {"user": {"login": "dan", "type": "User"}, "body": "@viewer can you\nlook?",
                           "html_url": "https://github.com/example/project/issues/7#issuecomment-99"}})
        rec = self.recorder(api)
        self.assertEqual(self.module.cleanup(api, apply=True, output=lambda _: None, recorder=rec), 0)
        [line] = self.records()
        cols = line.split("\t")
        self.assertEqual(cols[1:3], ["github", "🐙dan on example/project#7:"])
        self.assertIn("kind:mention type:Issue who:other thread:5 at:2026-10-22T08:00:00Z "
                      "link:https://github.com/example/project/issues/7#issuecomment-99 | ", cols[3])
        self.assertTrue(cols[3].endswith("| commented: @viewer can you look? · flaky e2e on main"))
        for token in cols[3].split(" | ")[0].split(" "):  # notify-watch's fields() rule
            self.assertRegex(token, r"^[a-z_]+:\S*$")
        self.assertEqual(rec.recorded, {"5": "2026-10-22T08:00:00Z"})

    def test_merged_pull_request_is_recorded_before_it_is_marked_done(self):
        item = notification(reason="author", repository=RECORD_REPO)
        merged = {"state": "closed", "merged": True, "merged_by": {"login": "viewer", "type": "User"}}
        at_delete = []
        api, calls = self.fake({
            LIST: [[item]], PR: merged, "/notifications/threads/1": item, "/user": {"login": "viewer"},
            "/repos/example/project/issues/123/comments?since=2026-10-22T07:45:00Z&per_page=100": []},
            log_at_delete=at_delete)
        rec = self.recorder(api)
        self.assertEqual(self.module.cleanup(api, apply=True, output=lambda _: None, recorder=rec), 0)
        self.assertEqual(calls[-1], ("DELETE", "/notifications/threads/1"))
        self.assertEqual(len(at_delete), 1)
        self.assertIn("🐙viewer on example/project#123:\tkind:author type:PullRequest who:self", at_delete[0])
        self.assertIn("| merged · ", at_delete[0])

    def test_pr_watch_prs_and_direct_review_requests_are_covered_quietly(self):
        link = "https://github.com/example/project/pull/123"
        for watched, direct, reason in (({link}, (), "comment"), ((), {link}, "review_requested")):
            with self.subTest(reason=reason):
                api, _ = self.fake({LIST: [[notification(reason=reason, repository=RECORD_REPO)]],
                                    PR: {"state": "open", "user": {"login": "dan", "type": "User"}}})
                rec = self.recorder(api, watched=watched, direct=direct)
                self.module.cleanup(api, apply=True, output=lambda _: None, recorder=rec)
                self.assertEqual(self.records(), [])
                self.assertEqual(rec.counts["covered"], 1)
                self.assertEqual(rec.recorded, {"1": "2026-10-22T08:00:00Z"})

    def test_a_team_review_request_on_a_human_pr_is_recorded(self):
        item = notification(reason="review_requested", repository=RECORD_REPO)
        api, _ = self.fake({LIST: [[item]], PR: {"state": "open", "user": {"login": "dan", "type": "User"}},
                            "/repos/example/project/issues/123/comments?since=2026-10-22T07:45:00Z&per_page=100": []})
        rec = self.recorder(api, direct={"https://github.com/example/project/pull/999"})
        self.module.cleanup(api, apply=True, output=lambda _: None, recorder=rec)
        [line] = self.records()
        self.assertIn("\t🐙example/project#123:\tkind:review_requested type:PullRequest who:-", line)

    def test_an_open_bot_pr_nobody_asked_about_stays_quiet(self):
        bot = {"state": "open", "body": "", "user": {"type": "Bot", "login": "renovate[bot]"},
               "requested_reviewers": [], "assignees": []}
        item = notification(reason="review_requested", repository=RECORD_REPO)
        api, _ = self.fake({LIST: [[item]], PR: bot, "/user": {"login": "viewer"}})
        rec = self.recorder(api)
        self.module.cleanup(api, apply=False, output=lambda _: None, recorder=rec)
        self.assertEqual(self.records(), [])
        self.assertEqual(rec.counts["bot_quiet"], 1)

    def test_an_unchanged_thread_is_recorded_once(self):
        api, _ = self.fake({LIST: [[self.issue_thread()]], "/user": {"login": "viewer"},
                            self.COMMENT: {"user": {"login": "dan"}, "body": "hi"}})
        rec = self.recorder(api)
        self.module.cleanup(api, apply=True, output=lambda _: None, recorder=rec)
        self.module.cleanup(api, apply=True, output=lambda _: None, recorder=rec)
        self.assertEqual(len(self.records()), 1)

    def test_first_run_seeds_threads_older_than_its_window(self):
        api, calls = self.fake({LIST: [[self.issue_thread()]]})
        rec = self.recorder(api, first_since=self.module.epoch_of("2026-10-22T09:00:00Z"))
        self.module.cleanup(api, apply=True, output=lambda _: None, recorder=rec)
        self.assertEqual(self.records(), [])
        self.assertEqual(rec.counts["seeded"], 1)
        self.assertEqual(rec.recorded, {"5": "2026-10-22T08:00:00Z"})
        self.assertNotIn(("GET", self.COMMENT), calls)

    def test_a_failed_comment_read_still_records_the_title(self):
        api, _ = self.fake({LIST: [[self.issue_thread()]],
                            self.COMMENT: self.module.APIError("boom", 502)})
        rec = self.recorder(api)
        self.assertEqual(self.module.cleanup(api, apply=True, output=lambda _: None, recorder=rec), 0)
        [line] = self.records()
        self.assertIn("\t🐙example/project#7:\tkind:mention type:Issue who:-", line)
        self.assertTrue(line.endswith("| Issue mention · flaky e2e on main"))

    def test_a_log_that_cannot_be_written_stops_recording_and_keeps_the_thread_unrecorded(self):
        api, _ = self.fake({LIST: [[self.issue_thread()]], "/user": {"login": "viewer"},
                            self.COMMENT: {"user": {"login": "dan"}, "body": "hi"}})
        rec = self.recorder(api)
        lines = []
        with mock.patch.object(self.module.os, "open", side_effect=PermissionError("denied")):
            status = self.module.cleanup(api, apply=True, output=lines.append, recorder=rec)
        self.assertEqual(status, 1)
        self.assertIn("ERROR: cannot append to notifications.log", "\n".join(lines))
        self.assertEqual(rec.recorded, {})
        self.assertTrue(rec.failed)
        self.assertIn("recorded=0", lines[-1])

    def test_preview_prints_records_and_writes_nothing(self):
        api, _ = self.fake({LIST: [[self.issue_thread()]], "/user": {"login": "viewer"},
                            self.COMMENT: {"user": {"login": "dan"}, "body": "hi"}})
        lines = []
        rec = self.module.Recorder(api, self.log, {}, set(), set(), write=False, output=lines.append, now=0)
        self.module.cleanup(api, apply=False, output=lines.append, recorder=rec)
        self.assertFalse(self.log.exists())
        self.assertTrue(any(line.startswith("RECORD: ") and "commented: hi" in line for line in lines))

    def test_entry_point_saves_recorded_and_no_record_writes_nothing(self):
        state = Path(self.dir.name) / "state" / "done.json"
        api, _ = self.fake({LIST: [[]]})
        with mock.patch.object(self.module, "github_api", api):
            self.assertEqual(self.module.main(["--apply", "--state-file", str(state), "--log", str(self.log),
                                               "--pr-watch-state", str(Path(self.dir.name) / "none.json")]), 0)
            self.assertEqual(json.loads((state.parent / "recorded.json").read_text()), {})
            (state.parent / "recorded.json").unlink()
            self.assertEqual(self.module.main(["--apply", "--no-record", "--state-file", str(state)]), 0)
            self.assertFalse((state.parent / "recorded.json").exists())

    def test_pr_watch_sets_read_its_state_and_fail_open(self):
        path = Path(self.dir.name) / "pr-watermarks.json"
        path.write_text(json.dumps({"_reviewRequests": ["https://github.com/a/b/pull/2"],
                                    "https://github.com/a/b/pull/1": {"headSha": "x"}}))
        self.assertEqual(self.module.pr_watch_sets(path),
                         ({"https://github.com/a/b/pull/1"}, {"https://github.com/a/b/pull/2"}))
        self.assertEqual(self.module.pr_watch_sets(path.with_name("missing.json")), (set(), set()))

    def test_html_url_maps_api_subjects(self):
        self.assertEqual(self.module.html_url("https://api.github.com/repos/a/b/pulls/3", "a/b"),
                         "https://github.com/a/b/pull/3")
        self.assertEqual(self.module.html_url("https://api.github.com/repos/a/b/issues/3", "a/b"),
                         "https://github.com/a/b/issues/3")
        self.assertEqual(self.module.html_url("https://api.github.com/repos/a/b/releases/9", "a/b"),
                         "https://github.com/a/b/releases")
        self.assertEqual(self.module.html_url(None, "a/b"), "https://github.com/a/b")


class CronIntegrationTest(unittest.TestCase):
    def test_documented_entry_is_recognized_by_the_cron_widget(self):
        root = SCRIPT.parents[1]
        documentation = (root / "scripts/github-notifications.md").read_text()
        entries = [line for line in documentation.splitlines() if line.startswith("7,22,37,52 ")]
        self.assertEqual(len(entries), 1)
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "crontab"
            fixture.write_text("# Mark closed PR notifications Done.\n" + entries[0] + "\n")
            environment = dict(os.environ, CRON_REGISTRY_FILE=str(fixture))
            result = subprocess.run(
                ["bash", "-c", 'source "$1"; cron_registry', "cron-fixture",
                 str(root / "scripts/__lib_cron_view.sh")],
                env=environment, capture_output=True, text=True, check=True,
            )
        fields = result.stdout.rstrip("\n").split("\t")
        self.assertEqual(fields[0], "7,22,37,52 8-19 * * 1-5")
        self.assertEqual(fields[1], "__github_notifications")
        self.assertEqual(fields[3], "Mark closed PR notifications Done.")


if __name__ == "__main__":
    unittest.main()
