import os
from pathlib import Path
import subprocess

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/__handoff_floater.sh'


def test_invalid_selection_is_logged_with_uuid_and_timestamp(tmp_path):
    env = dict(os.environ, XDG_STATE_HOME=str(tmp_path), XDG_RUNTIME_DIR=str(tmp_path))
    result = subprocess.run([str(SCRIPT), 'open', 'invalid', '%1'], env=env, capture_output=True, text=True)
    assert result.returncode == 2
    log = (tmp_path / 'handoff-floater.log').read_text()
    assert 'uuid=invalid mode=open Select a task with a full UUID' in log
    assert log[:4].isdigit()
