import importlib.util
import json
from datetime import datetime, timezone
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('ci_status', Path(__file__).resolve().parents[2] / 'scripts/__ci_project_status.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)
NOW = datetime(2026, 11, 11, 15, 0, tzinfo=timezone.utc)


def fixture():
    return {'project': {'issues': [
        {'identifier': 'DEVOPS-1', 'title': 'guard deployed', 'completedAt': '2026-11-11T10:00:00Z', 'state': {'type': 'completed'}, 'attachments': {'nodes': []}},
        {'identifier': 'DEVOPS-2', 'title': 'runner flag fix', 'completedAt': '2026-11-11T11:00:00Z', 'state': {'type': 'completed'}, 'attachments': {'nodes': []}},
        {'identifier': 'DEVOPS-3', 'title': 'active testing', 'completedAt': None, 'state': {'type': 'started'}, 'attachments': {'nodes': []}},
        {'identifier': 'DEVOPS-4', 'title': 'old fix', 'completedAt': '2026-10-01T11:00:00Z', 'state': {'type': 'completed'}, 'attachments': {'nodes': []}}]},
        'prs': {'https://github.com/a/b/pull/1': {'state': 'MERGED', 'title': 'guard', 'mergedAt': '2026-11-11T10:00:00Z'},
                'https://github.com/a/b/pull/2': {'state': 'MERGED', 'title': 'remove duplicate flag', 'mergedAt': '2026-11-11T11:00:00Z'},
                'https://github.com/a/b/pull/3': {'state': 'OPEN', 'title': 'active PR', 'mergedAt': None}}, 'deck': 'https://deck.test/ci'}


class StatusTest(unittest.TestCase):
    def test_merged_fixes_do_not_reappear_as_now_or_next(self):
        tasks = [{'status': 'pending', 'tags': ['piotr'], 'description': 'Guard deployed; review result', 'project': ci.PROJECT},
                 {'status': 'completed', 'tags': ['piotr'], 'description': 'Remove duplicate flag', 'project': ci.PROJECT}]
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / 'events'
            log.write_text('2026-11-11 10:00:00\tlinear\tDEVOPS-1 needs deploy\n2026-11-11 10:00:00\tlinear\tDEVOPS-2 remove flag\n')
            state = ci.resolve(fixture(), tasks, NOW, log)
        self.assertEqual(state['handoffs'], ['Guard deployed; review result'])
        self.assertFalse(any('deploy' in str(x) or 'duplicate' in str(x) for x in state['active']))
        self.assertNotIn('DEVOPS-4', [x['id'] for x in state['done']])
        self.assertIn('a/b#2', [x['id'] for x in state['done']])
        self.assertIn(('https://github.com/a/b/pull/3', 'active PR'), state['active'])

    def test_reject_unknown_and_open_ids_and_limits(self):
        candidates = ci.resolve(fixture(), [], NOW, Path('/nonexistent'))['done']
        valid = ['Guard live DEVOPS-1', 'Runner fixed DEVOPS-2', 'Guard merged a/b#1']
        self.assertEqual(ci.validate_done(valid, candidates), valid)
        for lines in ([*valid, 'Unknown DEVOPS-99'], [*valid, 'Still open DEVOPS-3'], valid[:2], [*valid, 'word ' * 13 + 'DEVOPS-1']):
            with self.assertRaises(ValueError):
                ci.validate_done(lines, candidates)

    def test_no_change_skips_model(self):
        candidates = ci.resolve(fixture(), [], NOW, Path('/nonexistent'))['done']
        response = ['Guard live DEVOPS-1', 'Runner fixed DEVOPS-2', 'Guard merged a/b#1']
        with tempfile.TemporaryDirectory() as temp:
            cache = Path(temp) / 'cache'
            def reply(command, **kwargs):
                Path(command[command.index('--out') + 1]).write_text(json.dumps(response))
            with patch.object(ci.subprocess, 'run', side_effect=reply) as run:
                self.assertEqual(ci.completed_summary(candidates, cache), response)
                self.assertEqual(ci.completed_summary(candidates, cache), response)
                self.assertEqual(run.call_count, 1)
                changed = list(candidates) + [{'id': 'DEVOPS-5', 'title': 'new', 'completed_at': NOW.isoformat(), 'kind': 'issue'}]
                ci.completed_summary(changed, cache)
                self.assertEqual(run.call_count, 2)

    def test_facts_merge_sources_and_description_is_a_plain_sentence(self):
        resolved = {'done': [], 'active': [], 'handoffs': []}
        done = ['Chromium download overlaps UI checks (DEVOPS-1, a/b#1)', 'Runner fixed (DEVOPS-2)']
        with patch.object(ci, 'resolve', return_value=resolved), patch.object(ci, 'completed_summary', return_value=done):
            status, _ = ci.generate({}, [])
        self.assertEqual(status['description'], 'CI infrastructure: Chromium download overlaps UI checks.')
        self.assertEqual(status['done'], ['Chromium download overlaps UI checks', 'Runner fixed'])
        brief = ci.format_brief(status, [])
        self.assertEqual(brief.count('Chromium download'), 1)
        self.assertTrue(brief.endswith('sources: DEVOPS-1, a/b#1, DEVOPS-2'))
        self.assertNotRegex(brief.split('sources:')[0], ci.ID)

    def test_acknowledgements_are_not_next_steps(self):
        tasks = [{'status': 'pending', 'tags': ['piotr', 'ack'], 'description': 'Read result', 'project': ci.PROJECT},
                 {'status': 'pending', 'tags': ['piotr'], 'description': 'Make decision', 'project': ci.PROJECT}]
        self.assertEqual(ci.resolve(fixture(), tasks, NOW, Path('/nonexistent'))['handoffs'], ['Make decision'])

    def test_project_issue_pr_and_deck_match_pending_only(self):
        tasks = [{'status': 'pending', 'tags': ['piotr'], 'description': 'Direct', 'project': ci.PROJECT},
                 {'status': 'pending', 'tags': ['piotr'], 'description': 'Linked', 'annotations': [{'description': 'a/b#2'}]},
                 {'status': 'completed', 'tags': ['piotr'], 'description': 'Done', 'project': ci.PROJECT}]
        self.assertEqual([t['description'] for t in ci.handoffs(tasks, fixture())], ['Direct', 'Linked'])
        self.assertEqual(ci.format_brief({'done':['a'], 'now':['b'], 'sources':['DEVOPS-1']}, ['Direct']), 'Done:\n- a\n\nNow:\n- b\n\nNext:\n- Direct\n\nsources: DEVOPS-1')


if __name__ == '__main__':
    unittest.main()
