"""Tab sweep native host: which tabs close, and what Gordon is told."""
import importlib.util
import json
import struct
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / 'scripts/__chrome_tab_sweep.py'
spec = importlib.util.spec_from_file_location('sweep_host', HOST)
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)

# Answers like `gh api graphql`: merged for keys in FAKE_MERGED, a null repo
# plus exit 1 for FAKE_MISSING, and one line per call in FAKE_GH_CALLS.
FAKE_GH = r'''#!/usr/bin/env python3
import json, os, re, sys
query = sys.argv[-1]
with open(os.environ["FAKE_GH_CALLS"], "a") as f:
    f.write(query + "\n")
if os.environ.get("FAKE_GH_FAIL"):
    sys.stderr.write("gh: HTTP 401: Bad credentials\n"); sys.exit(1)
merged = set(filter(None, os.environ.get("FAKE_MERGED", "").split(",")))
missing = set(filter(None, os.environ.get("FAKE_MISSING", "").split(",")))
data, errors = {}, []
for alias, owner, name, number in re.findall(r'(p\d+): repository\(owner: "([^"]+)", name: "([^"]+)"\) \{ pullRequest\(number: (\d+)\)', query):
    key = f"{owner}/{name}#{number}"
    if f"{owner}/{name}" in missing:
        data[alias] = None; errors.append({"type": "NOT_FOUND", "path": [alias]})
    else:
        data[alias] = {"pullRequest": {"merged": key in merged}}
print(json.dumps({"data": data, **({"errors": errors} if errors else {})}))
sys.exit(1 if errors else 0)
'''

FAKE_SND = r'''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["FAKE_SND_LOG"], "a") as f:
    f.write(json.dumps({"argv": sys.argv[1:], "from": os.environ.get("SND_FROM")}) + "\n")
sys.exit(int(os.environ.get("FAKE_SND_EXIT", "0")))
'''


def script(path, body):
    path.write_text(body)
    path.chmod(0o755)
    return path


@pytest.fixture
def fakes(tmp_path, monkeypatch):
    monkeypatch.setenv('TAB_SWEEP_GH', str(script(tmp_path / 'gh', FAKE_GH)))
    monkeypatch.setenv('TAB_SWEEP_SND', str(script(tmp_path / 'snd', FAKE_SND)))
    monkeypatch.setenv('FAKE_GH_CALLS', str(tmp_path / 'gh-calls'))
    monkeypatch.setenv('FAKE_SND_LOG', str(tmp_path / 'snd-log'))
    monkeypatch.delenv('TAB_SWEEP_TO', raising=False)
    return tmp_path


def tab(id, url, **extra):
    return {'id': id, 'url': url, 'title': f'tab {id}', 'windowId': 1, 'index': id, **extra}


def closing(result):
    return {row['id']: row['reason'] for row in result['close']}


def test_merged_pr_tabs_close_including_subpages_but_open_and_pinned_stay(fakes, monkeypatch):
    monkeypatch.setenv('FAKE_MERGED', 'loft-sh/vcluster#12')
    result = host.plan([
        tab(1, 'https://github.com/loft-sh/vcluster/pull/12'),
        tab(2, 'https://github.com/loft-sh/vcluster/pull/12/files#diff-1'),
        tab(3, 'https://github.com/loft-sh/vcluster/pull/13'),
        tab(4, 'https://github.com/loft-sh/vcluster/pull/12/checks', pinned=True),
        tab(5, 'https://github.com/loft-sh/vcluster/pull/120'),
    ])
    assert closing(result) == {1: 'merged', 2: 'merged'}
    assert result['close'][0]['pr'] == 'loft-sh/vcluster#12'
    assert result['errors'] == []


def test_duplicates_keep_pinned_then_active_then_first_copy(fakes):
    result = host.plan([
        tab(1, 'https://a.example/x'), tab(2, 'https://a.example/x', pinned=True), tab(3, 'https://a.example/x'),
        tab(4, 'https://b.example/'), tab(5, 'https://b.example/', active=True),
        tab(6, 'https://c.example/', windowId=2, index=0), tab(7, 'https://c.example/', windowId=1, index=9),
        tab(8, 'https://c.example/#top'),
    ])
    assert closing(result) == {1: 'duplicate', 3: 'duplicate', 4: 'duplicate', 6: 'duplicate'}


def test_an_agent_groups_copy_stays_and_the_ungrouped_copy_closes(fakes):
    result = host.plan([
        tab(1, 'https://a.example/', active=True), tab(2, 'https://a.example/', groupId=7),
        tab(3, 'https://b.example/', groupId=7), tab(4, 'https://b.example/', groupId=0),
        tab(5, 'https://c.example/', groupId=-1), tab(6, 'https://c.example/', groupId=-1),
    ])
    assert closing(result) == {1: 'duplicate', 6: 'duplicate'}


def test_two_pinned_copies_both_stay(fakes):
    result = host.plan([tab(1, 'https://a.example/', pinned=True), tab(2, 'https://a.example/', pinned=True)])
    assert result['close'] == []


def test_github_failure_closes_no_pr_tab_but_still_closes_duplicates(fakes, monkeypatch):
    monkeypatch.setenv('FAKE_GH_FAIL', '1')
    result = host.plan([tab(1, 'https://github.com/o/r/pull/1'), tab(2, 'https://x.example/'), tab(3, 'https://x.example/')])
    assert closing(result) == {3: 'duplicate'}
    assert result['errors'] == ['gh: gh: HTTP 401: Bad credentials']


def test_an_unresolvable_repo_leaves_its_tab_and_others_still_close(fakes, monkeypatch):
    monkeypatch.setenv('FAKE_MERGED', 'o/ok#1')
    monkeypatch.setenv('FAKE_MISSING', 'o/gone')
    result = host.plan([tab(1, 'https://github.com/o/ok/pull/1'), tab(2, 'https://github.com/o/gone/pull/1')])
    assert closing(result) == {1: 'merged'}


def test_many_prs_are_asked_in_batches_of_fifty(fakes, monkeypatch):
    monkeypatch.setenv('FAKE_MERGED', ','.join(f'o/r#{n}' for n in range(1, 61)))
    result = host.plan([tab(n, f'https://github.com/o/r/pull/{n}') for n in range(1, 61)])
    assert len(result['close']) == 60
    assert len((fakes / 'gh-calls').read_text().splitlines()) == 2


def test_report_dms_triage_with_prs_and_duplicate_urls_without_query(fakes):
    reply = host.report([
        {'id': 1, 'reason': 'merged', 'pr': 'loft-sh/vcluster#12', 'url': 'https://github.com/loft-sh/vcluster/pull/12'},
        {'id': 2, 'reason': 'duplicate', 'url': 'https://docs.example/page?token=secret#h'},
        {'id': 3, 'reason': 'duplicate', 'url': 'https://docs.example/page?token=secret#h'},
    ])
    assert reply == {'reported': True}
    call = json.loads((fakes / 'snd-log').read_text())
    assert call['from'] == 'tab-sweep'
    assert call['argv'][:3] == ['--no-human', '-t', 'triage']
    assert call['argv'][3] == ('Chrome tab sweep closed 3 tabs. Merged PRs (1): loft-sh/vcluster#12. '
                               'Duplicates (2): https://docs.example/page x2.')


def test_report_failure_is_returned_not_hidden(fakes, monkeypatch):
    monkeypatch.setenv('FAKE_SND_EXIT', '2')
    reply = host.report([{'id': 1, 'reason': 'duplicate', 'url': 'https://a/'}])
    assert reply == {'reported': False, 'error': 'snd exit 2'}


def test_nothing_closed_sends_nothing(fakes):
    assert host.report([])['reported'] is False
    assert not (fakes / 'snd-log').exists()


def test_a_report_op_without_an_explicit_ask_sends_nothing(fakes):
    closed = [{'id': 1, 'reason': 'duplicate', 'url': 'https://a/'}]
    assert host.handle({'op': 'report', 'closed': closed, 'auto': True}) == {'reported': False}
    assert not (fakes / 'snd-log').exists()
    assert host.handle({'op': 'report', 'closed': closed, 'report': True}) == {'reported': True}
    assert len((fakes / 'snd-log').read_text().splitlines()) == 1


def test_native_framing_round_trip(fakes):
    message = json.dumps({'op': 'plan', 'tabs': [tab(1, 'https://a/'), tab(2, 'https://a/')]}).encode()
    run = subprocess.run([sys.executable, str(HOST)], input=struct.pack('=I', len(message)) + message, capture_output=True, check=True)
    size = struct.unpack('=I', run.stdout[:4])[0]
    reply = json.loads(run.stdout[4:4 + size])
    assert [row['id'] for row in reply['close']] == [2]
