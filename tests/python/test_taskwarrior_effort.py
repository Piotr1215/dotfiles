"""Exercise the effort UDA and task reports with an isolated Taskwarrior database."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
REPORTS = (
    "currentall", "current", "private", "backlog", "current-home",
    "current-prs", "current-prs-age", "review", "inbox", "byrepo", "byproject",
    "workdone", "workdone-prs",
)


class EffortUdaTests(unittest.TestCase):
    def setUp(self):
        self.data = tempfile.TemporaryDirectory(prefix="task-effort-")
        self.addCleanup(self.data.cleanup)
        self.config = Path(self.data.name) / "taskrc"
        self.config.write_text(
            f"include {REPO / '.taskrc'}\ndata.location={self.data.name}\n"
            "hooks=off\ncontext=\nconfirmation=off\nrecurrence=off\ncolor=off\n"
        )
        self.env = {
            **os.environ, "TASKRC": str(self.config), "TASKDATA": self.data.name,
        }

    def task(self, *args, check=True):
        result = subprocess.run(
            ["task", f"rc.data.location={self.data.name}", "rc.hooks=off",
             "rc.context=", "rc.confirmation=off", "rc.recurrence=off",
             "rc.color=off", "rc.defaultwidth=300", *args],
            env=self.env,
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10,
        )
        if check:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_default_and_explicit_values(self):
        self.task("add", "project:effort-test", "default effort proof")
        self.assertEqual(json.loads(self.task("export").stdout)[0]["effort"], "high")
        for effort in ("medium", "high", "xhigh"):
            with self.subTest(effort=effort):
                self.task("1", "modify", f"effort:{effort}")
                self.assertEqual(json.loads(self.task("export").stdout)[0]["effort"], effort)

    def test_invalid_value_is_rejected(self):
        self.task("add", "default effort proof")
        result = self.task("1", "modify", "effort:invalid", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(self.task("export").stdout)[0]["effort"], "high")

    def test_report_columns_and_rendered_values(self):
        self.task("add", "project:effort-test", "effort:xhigh", "effort report proof")
        config = dict(
            line.strip().split("=", 1)
            for line in (REPO / ".taskrc").read_text().splitlines()
            if line.startswith("report.") and "=" in line
        )
        for report in REPORTS:
            with self.subTest(report=report):
                columns = config[f"report.{report}.columns"].split(",")
                labels = config[f"report.{report}.labels"].split(",")
                self.assertEqual(len(columns), len(labels))
                self.assertEqual(labels[columns.index("effort")], "Effort")
                rendered = self.task(f"rc.report.{report}.filter=status:pending", report).stdout
                self.assertIn("Effort", rendered)
                self.assertIn("xhigh", rendered)

    def test_selector_reads_real_task_uda(self):
        self.task("add", "selector effort proof")
        task_uuid = json.loads(self.task("export").stdout)[0]["uuid"]
        for suffix in ("model", "txt"):
            self.addCleanup(
                (Path("/tmp/claude-directives") / f"{task_uuid}.{suffix}").unlink,
                missing_ok=True,
            )
        script_dir = Path(self.data.name) / "selector"
        script_dir.mkdir()
        selector = script_dir / "__spawn_claude_directive.sh"
        shutil.copyfile(Path.home() / ".claude/scripts/__spawn_claude_directive.sh", selector)
        dialog = script_dir / "__spawn_directive_dialog.py"
        dialog.write_text(
            "#!/usr/bin/env python3\nimport json, os, pathlib, sys\n"
            "pathlib.Path(os.environ['DIALOG_ARGS_FILE']).write_text(json.dumps(sys.argv[1:]))\n"
            "print(json.dumps({'runner':'codex','directive':'','model':'gpt-6-astra'}))\n"
        )
        dialog.chmod(0o755)
        args_file = script_dir / "dialog-args.json"
        for effort in ("medium", "high", "xhigh"):
            with self.subTest(effort=effort):
                self.task("1", "modify", f"effort:{effort}", "-codex")
                result = subprocess.run(
                    ["bash", str(selector), "1"],
                    env={**self.env, "DIALOG_ARGS_FILE": str(args_file)},
                    capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                args = json.loads(args_file.read_text())
                self.assertEqual(args[args.index("--effort") + 1], effort)
                self.assertEqual(args[args.index("--desc") + 1], "selector effort proof")
                model = Path("/tmp/claude-directives") / f"{task_uuid}.model"
                self.assertEqual(model.read_text().strip(), "gpt-6-astra")
                record = json.loads(self.task("export").stdout)[0]
                self.assertEqual(record["effort"], effort)
                self.assertIn("codex", record["tags"])


if __name__ == "__main__":
    unittest.main()
