"""Group rename rules of the chrome-agent-tmux extension, run in node against a fake chrome API."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

HARNESS = Path(__file__).with_name('chrome_agent_tmux_fake_chrome.js')
NODE = shutil.which('node')
pytestmark = pytest.mark.skipif(NODE is None, reason='node not installed')


def run(tmp_path, *steps):
    scenario = tmp_path / 'scenario.json'
    scenario.write_text(json.dumps(list(steps)))
    out = subprocess.run([NODE, str(HARNESS), str(scenario)], capture_output=True, text=True, check=True, timeout=30)
    return json.loads(out.stdout)


def load():
    return {'do': 'load'}


def group(gid, title='Claude'):
    return {'do': 'group', 'group': gid, 'title': title}


def tab(tid, gid):
    return {'do': 'tab', 'tab': tid, 'group': gid}


def owns(tid, name):
    return {'do': 'map', 'tab': tid, 'name': name}


def title(gid, value):
    return {'do': 'title', 'group': gid, 'title': value}


def names_calls(result):
    return [h for h in result['host'] if h['message'].get('op') == 'names']


# Claude in Chrome puts a status emoji in front of "Claude" and rewrites it on each status change.
@pytest.mark.parametrize('reset,expected', [
    ('Claude', 'gordon'), ('claude', 'gordon'), ('CLAUDE', 'gordon'),
    ('\u2705Claude', '\u2705gordon'), ('\u23f3Claude', '\u23f3gordon'), ('\U0001f504 claude', '\U0001f504 gordon'),
])
def test_one_agent_titles_group(tmp_path, reset, expected):
    result = run(tmp_path, load(), owns(10, 'gordon'), owns(11, 'gordon'), group(1, reset), tab(10, 1), tab(11, 1))
    assert result['titles'] == {'1': expected}
    assert result['updates'] == [[1, expected]]
    assert all(h['name'] == 'org.piotr.agent_tab_tmux' for h in result['host'])


def test_several_agents_join_names(tmp_path):
    result = run(tmp_path, load(), owns(10, 'kendra'), owns(11, 'gordon'), group(1, '\u2705Claude'), tab(10, 1), tab(11, 1))
    assert result['titles'] == {'1': '\u2705gordon, kendra'}


def test_existing_groups_renamed_on_load(tmp_path):
    result = run(tmp_path, owns(10, 'gordon'), group(1, '\u2705Claude'), tab(10, 1), load())
    assert result['titles'] == {'1': '\u2705gordon'}


def test_unmapped_group_left_alone(tmp_path):
    result = run(tmp_path, load(), group(1, '\u2705Claude'), tab(10, 1), {'do': 'timers'}, {'do': 'timers'}, {'do': 'timers'})
    assert result['titles'] == {'1': '\u2705Claude'}
    assert result['updates'] == []
    assert result['timers'] == 0


def test_unmapped_then_hook_writes_retries(tmp_path):
    result = run(tmp_path, load(), group(1), tab(10, 1), owns(10, 'gordon'), {'do': 'timers'})
    assert result['titles'] == {'1': 'gordon'}


def test_status_rewrite_by_other_extension_is_reapplied(tmp_path):
    result = run(tmp_path, load(), owns(10, 'gordon'), group(1, '\u23f3Claude'), tab(10, 1), title(1, '\u2705Claude'))
    assert result['titles'] == {'1': '\u2705gordon'}
    assert result['updates'] == [[1, '\u23f3gordon'], [1, '\u2705gordon']]


def test_own_update_does_not_loop(tmp_path):
    result = run(tmp_path, load(), owns(10, 'gordon'), group(1, '\u2705Claude'), tab(10, 1))
    assert result['updates'] == [[1, '\u2705gordon']]
    # The echo of our own update must not even ask the host again.
    assert len(names_calls(result)) == 1
    assert result['timers'] == 0


def test_status_churn_is_not_capped(tmp_path):
    churn = [title(1, ('\u2705' if i % 2 else '\u23f3') + 'Claude') for i in range(12)]
    result = run(tmp_path, load(), owns(10, 'gordon'), group(1, '\u2705Claude'), tab(10, 1), *churn)
    assert len(result['updates']) == 13
    assert result['titles'] == {'1': '\u2705gordon'}


def test_identical_fight_backs_off(tmp_path):
    resets = [title(1, '\u2705Claude') for _ in range(12)]
    result = run(tmp_path, load(), owns(10, 'gordon'), group(1, '\u2705Claude'), tab(10, 1), *resets)
    assert len(result['updates']) == 3
    assert result['titles'] == {'1': '\u2705Claude'}


def test_tab_joining_our_group_adds_its_agent(tmp_path):
    result = run(tmp_path, load(), owns(10, 'gordon'), owns(11, 'kendra'), group(1, '\u2705Claude'), tab(10, 1),
                 {'do': 'timers'}, tab(11, 1))
    assert result['updates'] == [[1, '\u2705gordon'], [1, '\u2705gordon, kendra']]


def test_agent_named_claude_does_not_loop(tmp_path):
    result = run(tmp_path, load(), owns(10, 'claude'), group(1, '\u2705Claude'), tab(10, 1))
    assert result['updates'] == []


@pytest.mark.parametrize('steps', [
    [group(1, 'research'), tab(10, 1)],
    [group(1), tab(10, 1), title(1, 'mine'), tab(11, 1)],
])
def test_user_titles_left_alone(tmp_path, steps):
    result = run(tmp_path, load(), owns(10, 'gordon'), owns(11, 'kendra'), *steps)
    assert result['titles']['1'] in ('research', 'mine')
    assert all(t != 'gordon, kendra' for _, t in result['updates'])


def test_click_still_sends_switch_message(tmp_path):
    result = run(tmp_path, load(), group(1, 'research'), tab(10, 1), tab(11, 1), {'do': 'activate', 'tab': 11})
    switch = [h['message'] for h in result['host'] if 'op' not in h['message']]
    assert switch == [{'tabId': 11, 'groupId': 1, 'groupTabIds': [10, 11], 'owner': 'research'}]
