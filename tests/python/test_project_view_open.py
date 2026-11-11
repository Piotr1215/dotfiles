import os
from pathlib import Path
import subprocess


SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/__project_view_open.sh'


def executable(path, text):
    path.write_text('#!/bin/bash\n' + text + '\n')
    path.chmod(0o755)


def test_picker_and_viewer(tmp_path):
    home = tmp_path / 'home'
    views = home / '.local/state/project-views'
    views.mkdir(parents=True)
    page = views / 'ci-infra.md'
    page.write_text('# CI infrastructure\n')
    binaries = tmp_path / 'bin'
    binaries.mkdir()
    executable(binaries / 'fzf', 'head -n 1')
    executable(binaries / 'glow', 'printf "%s\\n" "$@"')
    env = {**os.environ, 'HOME': str(home), 'PATH': f'{binaries}:/usr/bin:/bin'}
    result = subprocess.run([str(SCRIPT)], env=env, capture_output=True, text=True)
    assert result.returncode == 0
    assert result.stdout.splitlines() == ['-p', str(page)]


def test_empty_directory_reports_error(tmp_path):
    result = subprocess.run([str(SCRIPT)], env={**os.environ, 'HOME': str(tmp_path)}, capture_output=True, text=True)
    assert result.returncode == 1
    assert 'No project views found' in result.stderr


def test_fallback_when_glow_missing(tmp_path):
    views = tmp_path / '.local/state/project-views'
    views.mkdir(parents=True)
    page = views / 'one.md'
    page.touch()
    binaries = tmp_path / 'bin'
    binaries.mkdir()
    executable(binaries / 'fzf', 'head -n 1')
    executable(binaries / 'less', 'printf "%s\\n" "$@"')
    result = subprocess.run([str(SCRIPT)], env={**os.environ, 'HOME': str(tmp_path), 'PATH': f'{binaries}:/usr/bin:/bin'}, capture_output=True, text=True)
    assert result.returncode == 0
    assert result.stdout.splitlines() == ['-R', str(page)]
