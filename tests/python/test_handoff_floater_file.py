#!/usr/bin/env python3
"""Exercise handoff preparation with the installed Taskwarrior brief helper."""

import json
import fcntl
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/__handoff_floater_file.py"
RENDERER = Path.home() / '.claude/scripts/__tw_brief.py'
SPEC = importlib.util.spec_from_file_location('tw_brief_renderer', RENDERER)
BRIEF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BRIEF)
UUID = "12345678-1234-1234-1234-123456789abc"


class HandoffFloaterFileTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.export = self.root / "export.json"
        self.command = self.root / "task"
        self.command.write_text(
            "#!/usr/bin/env python3\n"
            "import os, pathlib, sys\n"
            "assert sys.argv[1:-2] == ['rc.context=none', 'rc.hooks=off', "
            "'rc.verbose=nothing', 'rc.gc=off']\n"
            "assert sys.argv[-1] == 'export'\n"
            "print(pathlib.Path(os.environ['FAKE_TASK_EXPORT']).read_text())\n"
        )
        self.command.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(XDG_STATE_HOME=str(self.root / "state"),
                        HANDOFF_TASK_COMMAND=str(self.command),
                        HANDOFF_BRIEF_RENDERER=str(RENDERER),
                        FAKE_TASK_EXPORT=str(self.export))
        self.path = self.root / "state/taskwarrior/briefs" / UUID / "brief.md"
        self.task = {"uuid": UUID, "description": "Handoff title", "tags": ["draft"],
                     "annotations": [
                         {"entry": "20251231T000000Z", "description": "target: slack:C0123/1793917323.756099"},
                         {"entry": "20260101T000000Z", "description": "link: https://github.com/loft-sh/vcluster/pull/1"},
                         {"entry": "20260101T000000Z", "description": "draft: first draft"},
                         {"entry": "20260102T000000Z", "description": "draft: latest draft"},
                         {"entry": "20260103T000000Z", "description": "link: https://linear.app/loft/issue/DEVOPS-1"},
                     ]}
        self.write_export()

    def write_export(self):
        self.export.write_text(json.dumps([self.task]))

    def prepare(self, uid=UUID):
        return subprocess.run([sys.executable, str(SCRIPT), uid], env=self.env,
                              capture_output=True, text=True, check=False)

    def test_ci_view_brief_has_only_the_generated_sections(self):
        self.task.update(project='ci-infrastructure-improvements', tags=['view'], view_key='standing:pid', annotations=[{'entry': '20261111T120000Z', 'description': 'brief: Done:\n- Done item\n\nNow:\n- Now item\n\nNext:\n- Next item'}])
        self.write_export()
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(result.stdout.strip()).read_text(), 'Done:\n- Done item\n\nNow:\n- Now item\n\nNext:\n- Next item\n')

    def test_creates_missing_brief_and_seeds_latest_draft(self):
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.path))
        text = self.path.read_text()
        self.assertIn("# Handoff title", text)
        self.assertIn("<!-- begin generated draft -->\n" + BRIEF.fence_draft('latest draft') +
                      "\n<!-- end generated draft -->", text)
        self.assertNotIn("first draft", text)

    def test_seeds_open_block_from_target_then_links_without_drafts(self):
        self.assertEqual(self.prepare().returncode, 0)
        text = self.path.read_text()
        self.assertIn(
            "<!-- begin open -->\n"
            "https://loft-labs-inc.slack.com/archives/C0123/p1793917323756099?thread_ts=1793917323.756099\n"
            "https://github.com/loft-sh/vcluster/pull/1\n"
            "https://linear.app/loft/issue/DEVOPS-1\n"
            "<!-- end open -->",
            text,
        )
        self.assertNotIn("first draft", text.split("<!-- begin open -->", 1)[1])

    def test_repeat_preserves_edited_open_block(self):
        self.assertEqual(self.prepare().returncode, 0)
        text = self.path.read_text().replace(
            "https://github.com/loft-sh/vcluster/pull/1", "https://github.com/edited/review"
        )
        self.path.write_text(text)
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.path.read_text(), text)

    def test_repeat_preserves_manually_edited_draft(self):
        self.assertEqual(self.prepare().returncode, 0)
        self.path.write_text(self.path.read_text().replace("latest draft", "my edits"))
        edited = self.path.read_text()
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.path.read_text(), edited)

    def test_new_annotation_preserves_previous_edited_draft(self):
        self.assertEqual(self.prepare().returncode, 0)
        self.path.write_text(self.path.read_text().replace("latest draft", "my edits"))
        self.task["annotations"].append(
            {"entry": "20260103T000000Z", "description": "draft: newer draft"}
        )
        self.write_export()
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.path.read_text()
        self.assertIn("<!-- begin generated draft -->\n" + BRIEF.fence_draft('newer draft') +
                      "\n<!-- end generated draft -->", text)
        self.assertIn("## Previous edited draft\n\nmy edits", text)

    def test_refresh_replaces_fenced_generated_draft_and_preserves_fenced_user_edit(self):
        self.assertEqual(self.prepare().returncode, 0)
        old_user_text = 'manual edit\n<!-- end generated draft -->\n```\ninner code\n```'
        text = self.path.read_text()
        old_block = ("<!-- begin generated draft -->\n" + BRIEF.fence_draft(old_user_text) +
                     "\n<!-- end generated draft -->")
        start = text.index('<!-- begin generated draft -->')
        end = text.index('<!-- end generated draft -->', start) + len('<!-- end generated draft -->')
        self.path.write_text(text[:start] + old_block + text[end:])
        self.task['annotations'].append(
            {'entry': '20260105T000000Z', 'description': 'draft: replacement draft'}
        )
        self.write_export()

        result = self.prepare()

        self.assertEqual(result.returncode, 0, result.stderr)
        updated = self.path.read_text()
        self.assertIn("<!-- begin generated draft -->\n" + BRIEF.fence_draft('replacement draft') +
                      "\n<!-- end generated draft -->", updated)
        self.assertIn('## Previous edited draft\n\n' + old_user_text, updated)

    def test_legacy_renderer_without_fence_helpers_remains_compatible(self):
        legacy = self.root / 'legacy_renderer.py'
        legacy.write_text(
            'DRAFT_START = "<!-- begin generated draft -->"\n'
            'DRAFT_END = "<!-- end generated draft -->"\n'
            'def latest(task, prefix): return "new version"\n'
            'def markdown_lines(text):\n'
            ' for line in text.splitlines(): yield line, False\n'
        )
        self.env['HANDOFF_BRIEF_RENDERER'] = str(legacy)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(
            '# Handoff title\n\n## Draft\n\n<!-- begin generated draft -->\n'
            'my edits\n<!-- end generated draft -->\n'
        )
        self.task['annotations'].extend([
            {'entry': '20260104T000000Z', 'description': 'draft: original'},
            {'entry': '20260105T000000Z', 'description': 'draft: new version'},
        ])
        self.write_export()

        result = self.prepare()

        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.path.read_text()
        self.assertIn('<!-- begin generated draft -->\nnew version\n<!-- end generated draft -->', text)
        self.assertIn('## Previous edited draft\n\nmy edits', text)

    def test_prepare_defers_refresh_while_editor_holds_lock(self):
        self.assertEqual(self.prepare().returncode, 0)
        before = self.path.read_text()
        self.task['annotations'].append({'entry': '20260104T000000Z', 'description': 'draft: new draft'})
        self.write_export()
        with (self.path.parent.parent / '.editor.lock').open('a+') as lock:
            fcntl.flock(lock, fcntl.LOCK_SH)
            result = self.prepare()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.path.read_text(), before)
            self.path.write_text(before.replace('latest draft', 'my edit'))
            self.assertTrue((self.path.parent / '.prepare-pending').exists())
        result = subprocess.run([sys.executable, str(SCRIPT), '--refresh-pending'], env=self.env,
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('new draft', self.path.read_text())
        self.assertIn('my edit', self.path.read_text())
        self.assertFalse((self.path.parent / '.prepare-pending').exists())

    def test_invalid_target_reports_error_but_creates_brief(self):
        notifier = self.root / "notify-send"
        notifier.write_text(f"#!/bin/sh\ntouch {self.root / 'notified'}\n")
        notifier.chmod(0o755)
        self.env["PATH"] = f"{self.root}:{self.env['PATH']}"
        self.task["annotations"][0]["description"] = "target: slack:C0123/1793917323.756099 https://loft-labs-inc.slack.com/archives/C9999/p1793917323756099"
        self.write_export()
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Slack target and permalink disagree", result.stderr)
        self.assertIn(UUID, result.stderr)
        self.assertFalse((self.root / "notified").exists())
        self.assertIn("https://github.com/loft-sh/vcluster/pull/1", self.path.read_text())
        self.assertNotIn("/archives/C9999/", self.path.read_text().split("<!-- begin open -->", 1)[1])

    def regular_task(self):
        self.env['TZ'] = 'UTC'
        self.task = {'uuid': UUID, 'description': 'Write the controllers post', 'project': 'blog',
                     'tags': ['work', 'writing'], 'status': 'pending',
                     'due': '20261110T090000Z', 'scheduled': '20261108T070000Z',
                     'annotations': [
                         {'entry': '20261103T100000Z', 'description': 'second note'},
                         {'entry': '20261101T100000Z', 'description': 'first note'},
                     ]}
        self.write_export()
        return self.path.parent / '.task-details.md'

    def test_regular_task_details_list_fields_and_annotations_newest_last(self):
        sidecar = self.regular_task()

        result = self.prepare()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sidecar.read_text(), (
            '## Task\n\n'
            '- Description: Write the controllers post\n'
            '- Project: blog\n'
            '- Tags: work, writing\n'
            '- Status: pending\n'
            '- Due: 2026-11-10 09:00\n'
            '- Scheduled: 2026-11-08 07:00\n\n'
            '### Annotations\n\n'
            '- 2026-11-01 10:00 first note\n'
            '- 2026-11-03 10:00 second note\n'
        ))
        self.assertIn('# Write the controllers post', self.path.read_text())

    def test_regular_task_details_refresh_while_editor_holds_lock(self):
        sidecar = self.regular_task()
        self.assertEqual(self.prepare().returncode, 0)
        before = self.path.read_text()
        self.task['annotations'].append({'entry': '20261105T100000Z', 'description': 'newest note'})
        self.write_export()
        with (self.path.parent.parent / '.editor.lock').open('a+') as lock:
            fcntl.flock(lock, fcntl.LOCK_SH)
            result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.path.read_text(), before)
        self.assertTrue(sidecar.read_text().endswith('- 2026-11-05 10:00 newest note\n'))

    def test_regular_task_without_optional_fields_says_none(self):
        sidecar = self.regular_task()
        self.task = {'uuid': UUID, 'description': 'Bare task', 'status': 'pending'}
        self.write_export()

        self.assertEqual(self.prepare().returncode, 0)

        text = sidecar.read_text()
        for line in ('- Project: none', '- Tags: none', '- Due: none', '- Scheduled: none'):
            self.assertIn(line, text)
        self.assertTrue(text.endswith('### Annotations\n\nnone\n'))

    def test_annotation_cannot_open_a_fence_or_a_comments_section(self):
        sidecar = self.regular_task()
        self.task['annotations'] = [{'entry': '20261101T100000Z',
                                     'description': 'log:\n```bash\n## My comments\n# kept'}]
        self.write_export()

        self.assertEqual(self.prepare().returncode, 0)

        text = sidecar.read_text()
        self.assertIn('- 2026-11-01 10:00 log:\n  \\```bash\n  \\## My comments\n  # kept\n', text)
        self.assertEqual([line for line, fenced in BRIEF.markdown_lines(text) if fenced], [])

    def test_handoff_row_gets_no_details_and_drops_a_stale_one(self):
        sidecar = self.regular_task()
        self.assertEqual(self.prepare().returncode, 0)
        self.assertTrue(sidecar.exists())
        self.task['tags'].append('piotr')
        self.write_export()

        self.assertEqual(self.prepare().returncode, 0)

        self.assertFalse(sidecar.exists())

    def test_wrong_uuid_fails_without_creating_brief(self):
        result = self.prepare("different-uuid")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not open handoff brief:", result.stderr)
        self.assertFalse(self.path.exists())


if __name__ == "__main__":
    unittest.main()
