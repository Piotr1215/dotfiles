"""Test saving only the handoff brief's My comments section."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/__handoff_brief_save.py'
UUID = '12345678-1234-1234-1234-123456789abc'


class HandoffBriefSaveTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folder = self.root / 'state/taskwarrior/briefs' / UUID
        self.folder.mkdir(parents=True)
        self.brief = self.folder / 'brief.md'
        self.baseline = self.folder / '.piotr-baseline.md'
        self.export = self.root / 'task.json'
        self.log = self.root / 'commands.jsonl'
        self.task = {'uuid': UUID, 'description': 'Decide on rollout', 'tags': ['piotr'], 'annotations': []}
        self.export.write_text(json.dumps([self.task]))
        self.task_bin = self.write_command('task',
            '#!/usr/bin/env python3\n'
            'import json, os, pathlib, sys\n'
            'p=pathlib.Path(os.environ["FAKE_TASK_EXPORT"])\n'
            'rows=json.loads(p.read_text())\n'
            'if sys.argv[-1] == "export": print(p.read_text())\n'
            'else:\n rows[0]["annotations"].append({"description":sys.argv[-1]})\n p.write_text(json.dumps(rows))\n')
        self.tw = self.write_command('tw',
            '#!/usr/bin/env python3\n'
            'import json, os, subprocess, sys\n'
            'with open(os.environ["COMMAND_LOG"], "a") as f: f.write(json.dumps(["note",sys.argv[1:]])+"\\n")\n'
            'subprocess.run([os.environ["HANDOFF_TASK_COMMAND"],*sys.argv[1:]],check=True)\n')
        self.snd = self.write_command('snd',
            '#!/usr/bin/env python3\n'
            'import json, os, pathlib, sys\n'
            'with open(os.environ["COMMAND_LOG"], "a") as f: f.write(json.dumps(["dm",sys.argv[1:],os.environ.get("SND_FROM")])+"\\n")\n'
            'p=os.environ.get("FAIL_ONCE_FILE")\n'
            'if p and pathlib.Path(p).exists(): pathlib.Path(p).unlink(); sys.exit(7)\n')
        self.env = dict(os.environ, XDG_STATE_HOME=str(self.root / 'state'),
                        HANDOFF_TASK_COMMAND=str(self.task_bin), HANDOFF_TW_WRAPPER=str(self.tw),
                        HANDOFF_SND_COMMAND=str(self.snd), FAKE_TASK_EXPORT=str(self.export),
                        COMMAND_LOG=str(self.log),
                        # Keep these tests on the direct DM path and off the live intake log,
                        # however the file is run; the intake tests below override both.
                        INTAKE_DIRECT_DM='1', INTAKE_EVENTS_LOG=str(self.root / 'unused-events.log'))

    def write_command(self, name, text):
        path = self.root / name
        path.write_text(text)
        path.chmod(0o755)
        return path

    def call(self, mode):
        return subprocess.run([sys.executable, str(SCRIPT), mode, UUID], env=self.env,
                              capture_output=True, text=True, check=False)

    def rows(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_saves_comment_text_once(self):
        old = '# Brief\n\n## My comments\n\nold text\n\n## Details\n\nOriginal\n'
        self.brief.write_text(old)
        self.assertEqual(self.call('init').returncode, 0)
        self.brief.write_text('# Changed title\n\n## My comments\n\nnew text\n\n## Details\n\nEdited outside\n')
        result = self.call('save')
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = self.rows()
        self.assertEqual([row[0] for row in rows], ['note', 'dm'])
        self.assertIn('piotr-comment: -old text\n+new text', rows[0][1][2])
        self.assertNotIn('Changed title', rows[0][1][2])
        self.assertNotIn('Edited outside', rows[0][1][2])
        self.assertIn('> -old text\n> +new text', rows[1][1][-1])
        self.assertIn('Decide on rollout', rows[1][1][-1])
        self.assertEqual(rows[1][2], 'handoffs-file')
        self.assertEqual(self.baseline.read_text(), self.brief.read_text())

    def test_outside_edits_are_ignored_and_repeated_comment_is_new(self):
        self.brief.write_text('# Brief\n\n## My comments\n\n## Details\n\nBase\n')
        self.assertEqual(self.call('init').returncode, 0)
        self.brief.write_text('# Edited title\n\n## My comments\n\n## Details\n\nChanged\n')
        self.assertEqual(self.call('save').returncode, 0)
        self.assertFalse(self.log.exists())
        self.brief.write_text('# Edited title\n\n## My comments\n\nRepeat\n\n## Details\n\nChanged\n')
        self.assertEqual(self.call('save').returncode, 0)
        self.brief.write_text('# Edited title\n\n## My comments\n\nRepeat\nRepeat\n\n## Details\n\nChanged\n')
        self.assertEqual(self.call('save').returncode, 0)
        rows = self.rows()
        self.assertEqual([row[0] for row in rows], ['note', 'dm', 'note', 'dm'])
        self.assertIn('+Repeat', rows[0][1][2])
        self.assertIn('+Repeat', rows[2][1][2])

    def test_fenced_and_nested_headings_stay_in_my_comments(self):
        self.brief.write_text(
            '## My comments\n\nOld\n\n```md\n## Still a comment\n```\n\n'
            '### Nested heading\n\nMore text\n\n## Details\n\nOutside\n'
        )
        self.assertEqual(self.call('init').returncode, 0)
        self.brief.write_text(
            '## My comments\n\nNew\n\n```md\n## Still a comment\n```\n\n'
            '### Nested heading\n\nMore text\n\n## Details\n\nOutside\n'
        )
        self.assertEqual(self.call('save').returncode, 0)
        rows = self.rows()
        self.assertIn('+New', rows[0][1][2])
        self.assertNotIn('Outside', rows[0][1][2])

    def test_failed_delivery_retries_before_a_newer_edit(self):
        self.brief.write_text('## My comments\n\nStart\n')
        self.assertEqual(self.call('init').returncode, 0)
        fail = self.root / 'fail-once'
        fail.touch()
        self.env['FAIL_ONCE_FILE'] = str(fail)
        self.brief.write_text('## My comments\n\nFirst\n')
        self.assertNotEqual(self.call('save').returncode, 0)
        self.brief.write_text('## My comments\n\nSecond\n')
        result = self.call('save')
        self.assertEqual(result.returncode, 0, result.stderr)
        messages = [row[1][-1] for row in self.rows() if row[0] == 'dm']
        self.assertEqual(len(messages), 3)
        self.assertIn('+First', messages[0])
        self.assertIn('+First', messages[1])
        self.assertIn('+Second', messages[2])

    def test_regular_task_comment_reaches_the_task_and_triage(self):
        self.task['tags'] = ['work']
        self.export.write_text(json.dumps([self.task]))
        self.brief.write_text('# Task\n\n## My comments\n\n## Open\n')
        self.assertEqual(self.call('init').returncode, 0)
        self.brief.write_text('# Task\n\n## My comments\n\nremember the demo\n\n## Open\n')

        result = self.call('save')

        self.assertEqual(result.returncode, 0, result.stderr)
        rows = self.rows()
        self.assertEqual([row[0] for row in rows], ['note', 'dm'])
        self.assertIn('piotr-comment: +remember the demo', rows[0][1][2])
        self.assertEqual(rows[1][1][:3], ['--no-human', '-t', 'triage'])
        self.assertIn(f'Piotr commented on task {UUID} Decide on rollout:\n> +remember the demo', rows[1][1][-1])
        self.assertNotIn('handoff', rows[1][1][-1])
        self.assertEqual(rows[1][2], 'handoffs-file')
        self.assertEqual(self.baseline.read_text(), self.brief.read_text())

    def test_handoff_comment_names_the_handoff(self):
        self.brief.write_text('# Task\n\n## My comments\n\n## Open\n')
        self.assertEqual(self.call('init').returncode, 0)
        self.brief.write_text('# Task\n\n## My comments\n\nship it\n\n## Open\n')

        self.assertEqual(self.call('save').returncode, 0)

        self.assertIn(f'Piotr changed handoff {UUID} Decide on rollout:', self.rows()[1][1][-1])

    def intake_env(self, **extra):
        """The real emit helper writing to a temp log, never the live notifications.log."""
        self.intake_log = self.root / 'events.log'
        env = dict(self.env, HANDOFF_INTAKE_EMIT=str(Path.home() / '.claude/scripts/__intake_emit.py'),
                   INTAKE_EVENTS_LOG=str(self.intake_log), INTAKE_DIRECT_DM='0')
        env.update(extra)
        self.env = env

    def edit_brief(self, text):
        self.brief.write_text('# Task\n\n## My comments\n\n## Open\n')
        self.assertEqual(self.call('init').returncode, 0)
        self.brief.write_text(f'# Task\n\n## My comments\n\n{text}\n\n## Open\n')

    def test_intake_event_replaces_the_direct_dm(self):
        self.intake_env()
        self.edit_brief('ship it')

        result = self.call('save')

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([row[0] for row in self.rows()], ['note'])
        lines = self.intake_log.read_text().splitlines()
        self.assertEqual(len(lines), 1)
        stamp, source, title, tail = lines[0].split('\t')
        self.assertRegex(stamp, r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$')
        self.assertEqual(source, 'handoffs-file')
        self.assertEqual(title, f'Piotr changed handoff {UUID} Decide on rollout:\\n> +ship it')
        self.assertNotIn('\n', title)
        meta = tail.split(' | ')[0].split(' ')
        self.assertEqual(meta[:3], ['kind:brief-save', f'uuid:{UUID}', 'handoff:1'])
        save_id = meta[3].removeprefix('save_id:')
        self.assertRegex(save_id, r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')
        self.assertIn(f'[brief-save:{save_id}]', self.rows()[0][1][2])
        self.assertEqual(len(meta), 4)
        self.assertEqual(self.baseline.read_text(), self.brief.read_text())
        self.assertFalse((self.folder / '.piotr-pending-save.json').exists())

    def test_intake_event_marks_a_regular_task_as_not_a_handoff(self):
        self.intake_env()
        self.task['tags'] = ['work']
        self.export.write_text(json.dumps([self.task]))
        self.edit_brief('remember the demo')

        self.assertEqual(self.call('save').returncode, 0)

        self.assertFalse(any(row[0] == 'dm' for row in self.rows()))
        line = self.intake_log.read_text().splitlines()[0]
        self.assertIn(f'Piotr commented on task {UUID} Decide on rollout:\\n> +remember the demo', line)
        self.assertIn(' handoff:0 ', line)

    def test_direct_dm_switch_sends_the_old_dm_and_writes_no_event(self):
        self.intake_env(INTAKE_DIRECT_DM='1')
        self.edit_brief('ship it')

        result = self.call('save')

        self.assertEqual(result.returncode, 0, result.stderr)
        rows = self.rows()
        self.assertEqual([row[0] for row in rows], ['note', 'dm'])
        self.assertEqual(rows[1][1][:3], ['--no-human', '-t', 'triage'])
        self.assertIn(f'Piotr changed handoff {UUID} Decide on rollout:\n> +ship it', rows[1][1][-1])
        self.assertEqual(rows[1][2], 'handoffs-file')
        self.assertFalse(self.intake_log.exists() and self.intake_log.read_text())
        self.assertEqual(self.baseline.read_text(), self.brief.read_text())

    def test_missing_emit_helper_falls_back_to_the_direct_dm(self):
        self.intake_env(HANDOFF_INTAKE_EMIT=str(self.root / 'no-such-helper.py'))
        self.edit_brief('ship it')

        result = self.call('save')

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([row[0] for row in self.rows()], ['note', 'dm'])
        self.assertFalse(self.intake_log.exists())

    def test_failed_emit_and_failed_dm_keep_the_pending_save_for_retry(self):
        self.intake_env(HANDOFF_INTAKE_EMIT=str(self.write_command('emit-fails',
                        '#!/usr/bin/env python3\nimport sys\nsys.exit(1)\n')))
        self.edit_brief('First')
        fail = self.root / 'fail-once'
        fail.touch()
        self.env['FAIL_ONCE_FILE'] = str(fail)

        self.assertNotEqual(self.call('save').returncode, 0)
        self.assertTrue((self.folder / '.piotr-pending-save.json').exists())

        retry = self.call('save')

        self.assertEqual(retry.returncode, 0, retry.stderr)
        messages = [row[1][-1] for row in self.rows() if row[0] == 'dm']
        self.assertEqual(len(messages), 2)
        self.assertIn('+First', messages[1])
        self.assertFalse((self.folder / '.piotr-pending-save.json').exists())


if __name__ == '__main__':
    unittest.main()
