#!/usr/bin/env bash
# Audit configured backup coverage without running any backup.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec python3 - "$script_dir" "$@" <<'PY'
import fnmatch
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

script_dir = Path(sys.argv[1])
args = sys.argv[2:]
if args not in ([], ['--json']):
    sys.exit('usage: __backup_coverage.sh [--json]')
home = Path(os.environ['HOME'])
backup = Path(os.environ.get('BACKUP_COVERAGE_SOURCE', script_dir / '__backup.sh'))
patterns = Path(os.environ.get('BACKUP_COVERAGE_PATTERNS', home / '.backup_patterns'))
manifest = Path(os.environ.get('BACKUP_COVERAGE_MANIFEST', home / '.backup_coverage'))
try:
    source = backup.read_text()
    entries = {p.name: p for p in home.iterdir()}
    match = re.search(r'declare\s+-a\s+RESTIC_SOURCES=\((.*?)\n\s*\)', source, re.S)
    if not match:
        raise ValueError('RESTIC_SOURCES array not found')
    # Ask rsync itself to apply the home patterns and root .gitignore. The
    # extra rule prevents traversing the included directories.
    with tempfile.TemporaryDirectory(prefix='backup-coverage-') as dest:
        proc = subprocess.run(['rsync', '-an', '--out-format=%n',
            '--filter=dir-merge,- .gitignore', '--exclude=/*/*',
            '--exclude-from=' + str(patterns), str(home) + '/', dest + '/'],
            check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    mirror = {x.rstrip('/') for x in proc.stdout.splitlines() if x != './'}
    paths = re.findall(r'^\s*["\']([^"\']+)["\']', match.group(1), re.M)
    full, partial = set(), set()
    def add_path(raw):
        for prefix in ('/home/decoder/', '$HOME/', '${HOME}/', '$BACKUP_SOURCE_HOME/', '${BACKUP_SOURCE_HOME}/'):
            if raw.startswith(prefix):
                parts = raw[len(prefix):].strip('/').split('/')
                if parts[0]:
                    (full if len(parts) == 1 else partial).add(parts[0])
                break
    for path in paths:
        add_path(path)
    # Optional sources are declared in loops in the real backup script.
    for loop in re.finditer(r'for\s+[df]\s+in\s+([^;\n]+);\s*do\s*\n?\s*\[\[.*?RESTIC_SOURCES\+=', source, re.S):
        items = loop.group(1)
        if '$BACKUP_SOURCE_HOME' not in loop.group(0):
            continue
        for item in items.split():
            item = item.strip('"\'')
            if item.startswith('$BACKUP_SOURCE_HOME/'):
                pattern = item[len('$BACKUP_SOURCE_HOME/'):]
                for name in entries:
                    if fnmatch.fnmatchcase(name, pattern):
                        full.add(name)
            elif not item.startswith('$'):
                add_path('$HOME/' + item)
    for glob_pattern in re.findall(r'"\$BACKUP_SOURCE_HOME"/([^\s;]+)', source):
        if glob_pattern.startswith(('.password-store.bak', '.envrc.bak')):
            full.update(name for name in entries if fnmatch.fnmatchcase(name, glob_pattern))
    if '--tag downloads' in source and 'Downloads/' in source:
        full.add('Downloads')
    if '--tag browser' in source:
        partial.update(('.config', '.var'))
    if 'local_state_files "$BACKUP_SOURCE_HOME/dev" "$BACKUP_SOURCE_HOME/loft"' in source:
        partial.update(('dev', 'loft'))
    if '"$HOME/.local/state/taskwarrior/briefs"' in source:
        partial.add('.local')
    # Dedicated rsync sources cover these subtrees, with their own exclusions.
    dedicated_full, dedicated_partial = set(), set()
    for line in source.splitlines():
        if re.match(r'^\s*"[^|]+\|/home/decoder/', line):
            raw = line.split('|')[1]
            parts = raw[len('/home/decoder/'):].strip('/').split('/')
            (dedicated_full if len(parts) == 1 else dedicated_partial).add(parts[0])
    rules = {}
    for number, line in enumerate(manifest.read_text().splitlines(), 1):
        if not line or line.startswith('#'):
            continue
        fields = line.split('\t')
        if len(fields) != 3 or not fields[0] or '/' in fields[0] or fields[1] not in ('skip', 'later', 'unknown') or not fields[2] or fields[0] in rules:
            raise ValueError(f'invalid manifest line {number}')
        rules[fields[0]] = {'status': fields[1], 'reason': fields[2]}
    stale = sorted(set(rules) - set(entries))
    results = []
    for name, path in sorted(entries.items()):
        layers = []
        if name in full: layers.append('restic')
        elif name in partial: layers.append('restic (partial)')
        if name in mirror or name in dedicated_full: layers.append('mirror')
        elif name in dedicated_partial: layers.append('mirror (partial)')
        # Dedicated mirror sources were parsed above; dev is the entire source,
        # while loft/ops covers only one subtree.
        if name == '.task' and ('taskchampion.sqlite3' in source): layers.append('task')
        # A configured remote only protects commits actually pushed there.
        if path.is_dir() and not path.is_symlink() and (path / '.git').exists():
            remote = subprocess.run(['git', '-C', str(path), 'remote'], text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            if remote.returncode == 0 and remote.stdout.strip():
                label = 'github' if any(x in layers for x in ('restic', 'mirror', 'task')) else 'github-only'
                layers.append(label + ' (pushed commits only)')
        item = {'name': name, 'type': 'link' if path.is_symlink() else 'directory' if path.is_dir() else 'file',
                'target': os.readlink(path) if path.is_symlink() else None,
                'layers': layers, 'manifest': rules.get(name)}
        item['uncovered'] = not any(layer in ('restic', 'mirror', 'task') for layer in layers) and name not in rules
        item['mirror_no_history'] = 'mirror' in layers and 'restic' not in layers and 'task' not in layers
        results.append(item)
    uncovered = [x['name'] for x in results if x['uncovered']]
    data = {'uncovered': uncovered, 'stale': stale, 'entries': results}
    if args:
        print(json.dumps(data, ensure_ascii=True, indent=2))
    else:
        for name in uncovered: print('UNCOVERED: ' + name)
        for name in stale: print('STALE: ' + name)
        print('Configured layers only; exclusions and backup success are not verified.')
        for item in results:
            label = item['name']
            if item['type'] == 'link': label += ' -> ' + item['target']
            details = ', '.join(item['layers']) or 'no layer'
            if item['mirror_no_history']: details += ' (mirror only: no history)'
            if item['manifest']:
                details += '; ' + item['manifest']['status'] + ': ' + item['manifest']['reason']
            print(label + ': ' + details)
    sys.exit(2 if uncovered or stale else 0)
except (OSError, ValueError, subprocess.CalledProcessError) as e:
    print('backup coverage: ' + str(e), file=sys.stderr)
    sys.exit(1)
PY
