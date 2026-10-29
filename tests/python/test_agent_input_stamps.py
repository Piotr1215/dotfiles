"""Run the installed send functions with a private tmux stub."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.mark.parametrize(('script', 'function', 'argument', 'target'), [
    ('__mail_agent_spawn.sh', 'send_directive', '1', 'worker:main.1'),
    ('__cron_investigate.sh', 'send_directive', '1', 'worker:status.1'),
    ('__kctx_claude_notify.sh', 'send_to_pane', '%42', '%42'),
    ('__task_brief.sh', 'send_to_gordon', 'report to triage', '%42'),
])
@pytest.mark.parametrize('fail_stamp', [False, True])
def test_sender_marks_the_exact_pane_before_input(tmp_path, script, function, argument, target, fail_stamp):
    source = (ROOT / 'scripts' / script).read_text()
    start = re.search(rf'(?m)^{function}\(\) \{{\n', source).start()
    body = source[start:source.index('\n}', start) + 2]
    bindir = tmp_path / 'bin'
    bindir.mkdir()
    tmux = bindir / 'tmux'
    tmux.write_text(f'#!{sys.executable}\n' + '''import json, os, sys
args = sys.argv[1:]
with open(os.environ['TMUX_LOG'], 'a') as log:
    log.write(json.dumps(args) + '\\n')
if args[0] == 'list-panes':
    print('%42 triage')
if args[0] == 'set-option' and os.environ['FAIL_STAMP'] == '1':
    sys.exit(1)
''')
    tmux.chmod(0o755)
    log = tmp_path / 'tmux.jsonl'
    env = {**os.environ, 'PATH': str(bindir) + ':' + os.environ['PATH'],
           'TMUX_LOG': str(log), 'FAIL_STAMP': str(int(fail_stamp))}
    setup = "tmux_bin=tmux; TARGET=worker:main; SESSION=worker; directive='report to triage'; ENTER_DELAY=0; sleep() { :; };\n"
    result = subprocess.run(['bash', '-c', setup + body + f'\n{function} "$1" "report to triage"',
                             'sender-test', argument], env=env, capture_output=True, text=True)
    events = [json.loads(line) for line in log.read_text().splitlines()]
    sends = [i for i, args in enumerate(events) if args[0] == 'send-keys' and '-X' not in args]
    if fail_stamp:
        assert result.returncode != 0
        assert not sends
    else:
        assert result.returncode == 0, result.stderr
        assert sends
        for i in sends:
            assert events[i - 1][:-1] == ['set-option', '-p', '-t', target, '@agent_injected_at']
            assert events[i - 1][-1].isdecimal()
            assert events[i][1:3] == ['-t', target]
