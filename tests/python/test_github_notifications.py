"""Offline behavior tests for GitHub notification cleanup."""

import copy
import contextlib
import fcntl
import importlib.util
import io
import json
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


if __name__ == "__main__":
    unittest.main()
