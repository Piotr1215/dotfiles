import importlib.util
import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location('project_view_md', Path(__file__).resolve().parents[2] / 'scripts/__project_view_md.py')
md = importlib.util.module_from_spec(spec)
spec.loader.exec_module(md)
NOW = datetime(2026, 11, 11, 12, tzinfo=timezone.utc)


@pytest.fixture
def data():
    return {'project': {'url': 'https://linear.app/project/x', 'name': 'CI', 'issues': [
        {'identifier': 'DEVOPS-1', 'title': 'Finished', 'url': 'https://linear.app/issue/DEVOPS-1', 'completedAt': '2026-11-10T00:00:00Z', 'state': {'type': 'completed'}, 'projectMilestone': {'name': 'Build'}},
        {'identifier': 'DEVOPS-2', 'title': 'Working', 'url': 'https://linear.app/issue/DEVOPS-2', 'completedAt': None, 'state': {'type': 'started'}}]},
        'prs': {'https://github.com/o/r/pull/3': {'title': 'Open', 'state': 'OPEN', 'statusCheckRollup': [{'conclusion': 'FAILURE'}]}}, 'github_login': 'me'}


def test_done_uses_completed_candidates_and_one_link(data):
    def summary(candidates):
        assert [x['id'] for x in candidates] == ['DEVOPS-1']
        assert candidates[0]['milestone'] == 'Build'
        return ['Finished work (DEVOPS-1)']
    assert md.build_done(data, NOW, summary) == '- Finished work [DEVOPS-1](https://linear.app/issue/DEVOPS-1)'


def test_now_includes_issue_ci_agent_and_recent_slack(data):
    tasks = [{'project': md.ci.PROJECT, 'description': 'Run', 'annotations': [{'description': 'tmux session agent-one'}]}]
    events = '2026-11-11 11:00:00\tslack\t#proj-ci-infra\tlink:https://example.test/thread | update'
    text = md.build_now(data, tasks, ['agent-one'], events, NOW)
    assert all(x in text for x in ('DEVOPS-2', 'CI red', 'agent-one', 'example.test/thread'))


def test_next_orders_annotations_and_draft(data):
    tasks = [{'status': 'pending', 'project': md.ci.PROJECT, 'tags': ['piotr'], 'priority': 'L', 'entry': '20261110', 'description': 'later'},
             {'status': 'pending', 'project': md.ci.PROJECT, 'tags': ['piotr', 'draft'], 'priority': 'H', 'entry': '20261109', 'description': 'old',
              'annotations': [{'description': 'piotr-step: Post reply'}, {'description': 'link: https://example.test'}, {'description': 'draft: Hello'}]}]
    text = md.build_next(data, tasks, [{'url':'https://github.com/o/r/pull/3','title':'Review'}], [])
    assert text.startswith('1. Post reply')
    assert '```text\n   Hello\n   ```' in text
    assert text.index('later') < text.index('Review')


def test_atomic_write_replaces_file(tmp_path):
    dest = tmp_path / 'view.md'
    dest.write_text('old')
    md.atomic_write(dest, 'new')
    assert dest.read_text() == 'new'
    # conftest's autouse browser guard also lives in tmp_path; no temp file may.
    assert sorted(p.name for p in tmp_path.iterdir() if p.name != 'browser-guard') == ['view.md']
    assert dest.stat().st_mode & 0o777 == 0o600


def test_failures_keep_last_good_sections(tmp_path, monkeypatch):
    dest, cache = tmp_path/'view.md', tmp_path/'cache.json'
    old = {x: {'text': 'saved '+x, 'at': '2026-11-11T10:00:00+00:00'} for x in ('Done', 'Now', 'Next for you')}
    cache.write_text(json.dumps(old))
    monkeypatch.setattr(md, 'OUT', dest)
    monkeypatch.setattr(md, 'CACHE', cache)
    monkeypatch.setattr(md, 'PAGE', tmp_path/'missing')
    monkeypatch.setattr(md, 'task_export', lambda: [])
    monkeypatch.setattr('sys.argv', ['script', 'ci-infra'])
    assert md.main() == 1
    text = dest.read_text()
    assert text.count('stale since') == 3
    assert 'saved Done' in text and 'saved Now' in text and 'saved Next for you' in text
