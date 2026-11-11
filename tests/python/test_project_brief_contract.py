"""Exercise the refresh-to-reader contract through an isolated Taskwarrior DB."""

import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest import mock


REPO = Path(__file__).resolve().parents[2]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, REPO / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


refresh = load("contract_refresh", "__project_view_refresh.py")
reader = load("contract_reader", "__handoff_floater_file.py")


@unittest.skipUnless(shutil.which("task"), "Taskwarrior is required for the reader contract")
class ProjectBriefContract(unittest.TestCase):
    def test_refresh_import_and_reader_share_identity_content_and_quiet_rereads(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            data = root / "data"
            data.mkdir()
            rc = root / "taskrc"
            rc.write_text(f"data.location={data}\nhooks=off\nconfirmation=off\n")
            task = shutil.which("task")
            state = root / "state"
            uid = "12345678-1234-4234-8234-123456789abc"
            key = "standing:contract-project"
            now = datetime(2026, 11, 11, 12, tzinfo=UTC)
            original = {
                "uuid": uid, "entry": "20261101T000000Z", "status": "pending",
                "tags": ["view"], "view_key": key, "project": "contract-project",
                "description": "Previous overview", "annotations": [],
            }
            environment = {
                "HOME": str(root), "TASKRC": str(rc), "TASKDATA": str(data),
                "XDG_STATE_HOME": str(state), "HANDOFF_TASK_COMMAND": task,
                # A project context must never import the editable handoff renderer.
                "HANDOFF_BRIEF_RENDERER": str(root / "must-not-load.py"),
            }
            with mock.patch.dict(os.environ, environment), \
                    mock.patch.object(refresh, "TASK_CMD", [task]), \
                    mock.patch.object(refresh, "BRIEFS_DIR", state / "taskwarrior/briefs"):
                refresh.apply([original])
                for version in (1, 2):
                    result = subprocess.run(
                        [task, "rc.context=none", "rc.hooks=off", "rc.gc=off", "export"],
                        check=True, capture_output=True, text=True,
                    )
                    existing = json.loads(result.stdout)
                    text = f"# Contract project\n\n## Done\nEvidence {version}.\n\n## Now\nReview in progress.\n"
                    rows = {key: {
                        "project": "contract-project", "rank": 9,
                        "description": "standing: Contract project",
                        "annotations": ["brief: " + text],
                    }}
                    payload, _ = refresh.plan(rows, {}, existing, now + timedelta(minutes=version))
                    refresh.apply(payload)
                    refresh.publish_contexts(rows, existing)
                    path = state / "taskwarrior/briefs" / uid / "project-status.md"
                    self.assertEqual(path.read_text(), text)
                    stamp = path.stat().st_mtime_ns
                    for _ in range(2):
                        output = io.StringIO()
                        with contextlib.redirect_stdout(output):
                            reader.prepare(uid)
                        self.assertEqual(output.getvalue().strip(), str(path))
                        self.assertEqual(path.read_text(), text)
                        self.assertEqual(path.stat().st_mtime_ns, stamp)
                    self.assertFalse(path.with_name("brief.md").exists())


if __name__ == "__main__":
    unittest.main()
