"""Exercise the configured handoff filter against isolated TaskWarrior data."""
import os
from pathlib import Path
import subprocess

import pytest


@pytest.mark.parametrize("finish", ["settled", "completed"])
def test_blocked_draft_is_hidden_until_dependency_released(tmp_path, finish):
    config = Path(__file__).resolve().parents[2] / '.taskrc'
    report_filter = next(line.partition('=')[2] for line in config.read_text().splitlines()
                         if line.startswith('report.handoffs.filter='))
    rc = tmp_path / 'taskrc'
    rc.write_text(f'data.location={tmp_path}\nhooks=off\nconfirmation=off\n'
                  'report.check.description=check\nreport.check.columns=description\n'
                  'report.check.labels=description\nreport.check.filter=' + report_filter + '\n')
    env = dict(os.environ, TASKRC=str(rc), TASKDATA=str(tmp_path))
    def task(*args):
        return subprocess.run(['task', 'rc.color=off', 'rc.verbose=nothing', *args], env=env,
                              capture_output=True, text=True, check=True).stdout
    task('add', '+piotr', 'blocker')
    task('add', '+piotr', '+draft', 'depends:1', 'draft')
    assert 'blocker' in task('check')
    assert 'draft' not in task('check')
    if finish == 'settled':
        task('1', 'modify', '+settled')
        task('2', 'modify', 'depends:-1')
    else:
        task('1', 'done')
    assert 'draft' in task('check')
