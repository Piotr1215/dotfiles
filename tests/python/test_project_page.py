import importlib.util
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('project_page', Path(__file__).resolve().parents[2] / 'scripts/__project_page.py')
page = importlib.util.module_from_spec(spec)
spec.loader.exec_module(page)


def connection(nodes):
    return {'nodes': nodes, 'pageInfo': {'hasNextPage': False, 'endCursor': None}}


def fixture():
    issue = {'identifier': 'DEVOPS-123', 'title': 'Fix builds', 'url': 'https://linear.app/test/123', 'updatedAt': '2026-11-11T10:00:00+00:00', 'completedAt': None, 'priority': 1, 'state': {'name': 'In Progress', 'type': 'started'}, 'assignee': {'name': 'Piotr', 'isMe': True}, 'projectMilestone': {'id': 'm', 'name': 'First'}, 'labels': connection([{'name': 'Blocked'}]), 'attachments': connection([{'url': 'https://github.com/a/b/pull/1', 'title': 'PR'}, {'url': 'https://x.slack.com/archives/C/p1', 'title': 'Thread'}]), 'history': connection([{'createdAt': '2026-11-11T09:00:00+00:00', 'fromState': {'name': 'Todo'}, 'toState': {'name': 'In Progress'}}]), 'comments': connection([{'createdAt': '2026-11-11T09:30:00+00:00', 'url': 'https://linear.app/comment'}]), 'inverseRelations': connection([])}
    pr = {'url': 'https://github.com/a/b/pull/1', 'title': 'Fix', 'state': 'OPEN', 'createdAt': '2026-11-11T08:00:00+00:00', 'mergedAt': None, 'statusCheckRollup': [{'conclusion': 'SUCCESS'}], 'reviewRequests': [{'login': 'piotr'}]}
    return {'project': {'name': 'Test', 'url': 'https://linear.app/project', 'targetDate': '2026-12-01', 'projectUpdates': connection([{'createdAt': '2026-11-10', 'health': 'onTrack', 'url': 'https://linear.app/update'}]), 'projectMilestones': connection([{'id': 'm', 'name': 'First'}]), 'issues': [issue]}, 'prs': {pr['url']: pr}, 'tasks': [{'description': 'Task', 'status': 'pending', 'tags': ['piotr'], 'project': 'ci-infrastructure-improvements'}], 'github_login': 'piotr', 'deck': 'https://example.com/deck', 'ci_events': []}


class ProjectPageTest(unittest.TestCase):
    def test_summary_keeps_cited_sentences_and_bold_heading(self):
        response = ('DEVOPS-123 moved to Released after a/b#1 was merged.\n'
                    'An unsupported statement. another unsupported statement (DEVOPS-999).\n**Next steps**\n\n'
                    '- Walk through the network (DEVOPS-123, Todo).\n'
                    '- Invented issue (DEVOPS-999).\n')
        def run(cmd, **kwargs):
            Path(cmd[cmd.index('--out') + 1]).write_text(response)
            return unittest.mock.Mock(returncode=0)
        with patch.object(page.subprocess, 'run', side_effect=run):
            result = page.summary(fixture())
        self.assertEqual(result, 'DEVOPS-123 moved to Released after a/b#1 was merged.\nNext steps\n- Walk through the network (DEVOPS-123, Todo).')

    def test_render_all_sections_and_escape(self):
        data = fixture()
        data['project']['issues'][0]['title'] = '<script>'
        todo = copy.deepcopy(data['project']['issues'][0])
        todo.update(identifier='DEVOPS-124', title='Next work', state={'name': 'Todo', 'type': 'unstarted'})
        done = copy.deepcopy(todo)
        done.update(identifier='DEVOPS-125', title='Finished work', state={'name': 'Done', 'type': 'completed'}, completedAt='2026-11-10T10:00:00+00:00')
        data['project']['issues'].extend([todo, done])
        data['tasks'][0]['annotations'] = [{'description': 'target: slack:C123/1234567890.123456'}]
        result = page.render(data, 'Work continues (DEVOPS-123).\nNext steps\n- Fix builds (DEVOPS-123)', '2026-11-11T12:00:00+00:00')
        for name in ('Where it stands', 'Changed in the last 24 hours', 'Waiting on Piotr', 'In progress', 'Next', 'Done in the last 14 days', 'Blocked', 'Conversations', 'Links'):
            self.assertIn(name, result)
        for text in ('&lt;script&gt;', 'First: 1/3', 'CI green', 'new comment', 'Thread', 'Project deck', 'content="300"', 'DEVOPS-124 Next work', 'DEVOPS-125 Finished work', 'https://loft-labs-inc.slack.com/archives/C123/p1234567890123456'):
            self.assertIn(text, result)
        self.assertNotIn('<script>', result)

    def test_refresh_writes_json_and_no_html_or_model(self):
        data = fixture()
        with tempfile.TemporaryDirectory() as tmp, patch.object(page, 'STATE', Path(tmp)), patch.object(page.view, 'linear_key', return_value='stub'), patch.object(page.view, 'task_json', return_value=data['tasks']), patch.object(page, 'collect_project', return_value=data['project']), patch.object(page, 'read_prs', return_value=data['prs']), patch.object(page, 'deck_url', return_value=data['deck']), patch.object(page.subprocess, 'run') as run, patch.object(page, 'summary') as summary:
            run.return_value.stdout = 'piotr\n'
            page.main()
            self.assertTrue((Path(tmp) / 'ci-infra.json').exists())
            self.assertFalse((Path(tmp) / 'ci-infra.html').exists())
            summary.assert_not_called()

    def test_github_collection_uses_attached_prs(self):
        data = fixture()
        pr = next(iter(data['prs'].values()))
        with patch.object(page.subprocess, 'run') as run:
            run.return_value.returncode = 0
            run.return_value.stdout = json.dumps(pr)
            self.assertEqual(page.read_prs(data['project']['issues']), data['prs'])
            self.assertEqual(run.call_count, 1)
            self.assertIn('statusCheckRollup', run.call_args.args[0][-1])

    def test_next_skips_empty_next_milestone(self):
        data = fixture()
        issue = data['project']['issues'][0]
        issue['state'] = {'name': 'Todo', 'type': 'unstarted'}
        data['project']['projectMilestones']['nodes'].insert(0, {'id': 'empty', 'name': 'Empty', 'status': 'next', 'sortOrder': -1})
        result = page.render(data, '', '2026-11-11T12:00:00+00:00')
        next_section = result.split('<h2>Next</h2>', 1)[1].split('</section>', 1)[0]
        self.assertIn('DEVOPS-123', next_section)

    def test_ci_status(self):
        self.assertEqual(page.ci({'statusCheckRollup': [{'conclusion': 'FAILURE'}]}), 'red')
        self.assertEqual(page.ci({'statusCheckRollup': [{'state': 'PENDING'}]}), 'pending')
        self.assertEqual(page.ci({'statusCheckRollup': [{'conclusion': 'SUCCESS'}]}), 'green')


if __name__ == '__main__':
    unittest.main()
