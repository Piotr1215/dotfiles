#!/usr/bin/env bash
set -eo pipefail

# Keep all restored data in a fresh local scratch directory, never a live path.
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export DRILL_SCRATCH="$T"
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/mnt/nas-backup/secure-store}"
export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-$HOME/.config/restic/password}"
python3 - "$@" <<'PY'
import datetime, json, os, pathlib, random, shutil, sqlite3, subprocess, sys, time

home = pathlib.Path(os.environ['HOME'])
nas = pathlib.Path(os.getenv('BACKUP_ROOT', '/mnt/nas-backup'))
tmp = pathlib.Path(os.environ['DRILL_SCRATCH'])
state = pathlib.Path(os.getenv('BACKUP_DRILL_STATE', str(home / '.local/state/backup-drill/last.json')))
task_copy = pathlib.Path(os.getenv('TASK_SNAPSHOT_PATH', str(home / '.local/share/task-backups'))) / 'taskchampion.sqlite3'
layers = ['restic', 'home', 'dev', 'task', 'system', 'taskchampion']
if len(sys.argv) == 3 and sys.argv[1] == '--layer' and sys.argv[2] in layers:
    selected = [sys.argv[2]]
elif len(sys.argv) == 1:
    selected = layers
else:
    print('usage: __backup_drill.sh [--layer ' + '|'.join(layers) + ']', file=sys.stderr)
    sys.exit(2)

# Run a read-only command without exposing diagnostic output containing paths or secrets.
def run(*args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=300)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed (exit {result.returncode})')
    return result.stdout

# Inspect an SQLite copy in read-only mode and count its task rows.
def database(path):
    with sqlite3.connect(path.as_uri() + '?mode=ro&immutable=1', uri=True) as db:
        check = db.execute('pragma integrity_check').fetchall()
        if check != [('ok',)]:
            raise RuntimeError('SQLite integrity_check failed')
        return db.execute('select count(*) from tasks').fetchone()[0]

# Compare stable files after first copying them into scratch.
def compare(source, mirror, dest):
    before = source.stat()
    shutil.copyfile(mirror, dest)
    import filecmp
    if not filecmp.cmp(source, dest, shallow=False):
        raise RuntimeError(f'restored file differs from live file: {source}')
    after = source.stat()
    if (before.st_mtime_ns, before.st_size) != (after.st_mtime_ns, after.st_size):
        raise RuntimeError('live file changed during comparison')

# Pick random eligible regular files without following links out of the mirror.
def mirror_check(name):
    mirror = nas / name
    live = home if name == 'home' else home / 'dev'
    stamp = 0
    try:
        label = 'system files' if name == 'home' else 'dev folder'
        for line in (home / 'backup.log').read_text().splitlines():
            if f'{label} backup completed successfully' in line:
                stamp = max(stamp, int(time.mktime(time.strptime(line[1:20], '%Y-%m-%d %H:%M:%S'))))
    except (OSError, ValueError):
        pass
    if not stamp:
        stamp = int((home / '.local/state/backup-last-success').read_text().strip())
    if not mirror.is_dir() or stamp <= 0:
        raise RuntimeError('mirror or successful nightly timestamp missing')
    sample = []
    for root, dirs, files in os.walk(mirror, followlinks=False):
        # These home-mirror destinations are populated from other sources by
        # __backup.sh, or generated there, rather than mirrored from ~/.
        if name == 'home' and pathlib.Path(root) == mirror:
            dirs[:] = [d for d in dirs if d not in {'cron', 'systemd_backup', 'obs', 'argos', 'tlp', 'zoxide', 'eve-preview-manager'}]
            files = [f for f in files if f != 'pop_os_settings_backup.ini']
        random.shuffle(dirs)
        random.shuffle(files)
        for file in files:
            p = pathlib.Path(root) / file
            source = live / p.relative_to(mirror)
            try:
                if p.is_symlink() or not p.is_file() or source.is_symlink() or not source.is_file() or source.stat().st_mtime >= stamp:
                    continue
                sample.append((source, p))
                if len(sample) == 5:
                    break
            except OSError:
                continue
        if len(sample) == 5:
            break
    if len(sample) < 5:
        raise RuntimeError(f'only {len(sample)} eligible files; need 5')
    for i, (source, p) in enumerate(sample):
        compare(source, p, tmp / f'{name}-{i}')
    return '5 restored files match'

# Restore the newest copy of the task DB and sample three files from the newest nightly snapshot.
def restic_check():
    snapshots = json.loads(run('restic', 'snapshots', '--no-lock', '--json'))
    nightly = [s for s in snapshots if str(task_copy.parent) in [p.rstrip('/') for p in s.get('paths', [])] and 'browser' not in s.get('tags', [])]
    nightly.sort(key=lambda s: s['time'], reverse=True)
    if not nightly:
        raise RuntimeError('no nightly snapshot contains the task backup directory')
    containing = [s for s in snapshots if any(str(task_copy) == p.rstrip('/') or str(task_copy).startswith(p.rstrip('/') + '/') for p in s.get('paths', []))]
    containing.sort(key=lambda s: s['time'], reverse=True)
    chosen = None
    for snap in containing:
        listing = run('restic', 'ls', '--no-lock', '--json', snap['id'], str(task_copy.parent))
        if any(x.get('path') == str(task_copy) and x.get('type') == 'file' for x in map(json.loads, listing.splitlines())):
            chosen = snap
            break
    if chosen is None:
        raise RuntimeError('task DB not found in snapshots')
    run('restic', 'restore', '--no-lock', chosen['id'], '--target', str(tmp), '--include', str(task_copy))
    rows = database(tmp / str(task_copy).lstrip('/'))
    snap = nightly[0]
    cutoff = datetime.datetime.fromisoformat(snap['time'].replace('Z', '+00:00')).timestamp()
    # Reservoir sampling avoids storing the full potentially large listing.
    proc = subprocess.Popen(['restic', 'ls', '--no-lock', '--json', '--recursive', snap['id']], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    candidates = []
    seen = 0
    for line in proc.stdout:
        node = json.loads(line)
        path = node.get('path', '')
        if node.get('type') != 'file' or not 0 < node.get('size', 0) <= 1048576 or not path.startswith(str(home) + '/') or any(c in path for c in '*?[]\\\n'):
            continue
        p = pathlib.Path(path)
        try:
            if p.is_symlink() or not p.is_file() or p.stat().st_mtime >= cutoff:
                continue
        except OSError:
            continue
        seen += 1
        if len(candidates) < 3:
            candidates.append(p)
        else:
            n = random.randrange(seen)
            if n < 3:
                candidates[n] = p
    if proc.wait() != 0:
        raise RuntimeError('restic snapshot listing failed')
    if len(candidates) < 3:
        raise RuntimeError(f'only {len(candidates)} eligible snapshot files; need 3')
    for p in candidates:
        run('restic', 'restore', '--no-lock', snap['id'], '--target', str(tmp), '--include', str(p))
        restored = tmp / str(p).lstrip('/')
        before = p.stat()
        if before.st_mtime >= cutoff:
            raise RuntimeError('live file changed since snapshot')
        import filecmp
        if not filecmp.cmp(p, restored, shallow=False) or p.stat().st_mtime_ns != before.st_mtime_ns:
            raise RuntimeError('restored snapshot file differs from live file')
    return f'task DB integrity ok, {rows} rows; 3 restored files match'

# Check files from both state directories in the mirror.
def task_check():
    sources = [home / '.local/state/taskwarrior/briefs', home / '.local/state/gordon']
    try:
        stamp = int((nas / 'taskwarrior-mirror/.dirs-ok-at').read_text().strip())
        if stamp <= 0:
            raise ValueError('invalid timestamp')
    except (OSError, ValueError):
        raise RuntimeError('task state mirror success timestamp missing or invalid') from None
    checked = 0
    for source in sources:
        mirror = nas / 'taskwarrior-mirror/state' / str(source).lstrip('/')
        if not source.is_dir() or not mirror.is_dir():
            raise RuntimeError('task state source or mirror directory missing')
        files = [p for p in source.rglob('*') if p.is_file() and not p.is_symlink() and p.stat().st_mtime < stamp]
        random.shuffle(files)
        for p in files[:3]:
            target = mirror / p.relative_to(source)
            if target.is_symlink() or not target.is_file():
                raise RuntimeError('task state file missing from mirror')
            import filecmp
            before = p.stat()
            if not filecmp.cmp(p, target, shallow=False) or p.stat().st_mtime_ns != before.st_mtime_ns:
                raise RuntimeError('task state mirror differs or changed during comparison')
            checked += 1
    return f'{checked} state files match across briefs and Gordon state'

# Restore and compare fstab from the weekly mirror.
def system_check():
    source = pathlib.Path(os.getenv('BACKUP_FSTAB', '/etc/fstab'))
    compare(source, nas / 'system-backup/etc/fstab', tmp / 'fstab')
    return 'restored fstab matches'

# Restore a fresh TaskChampion database using only the live sync settings.
def server_check():
    settings = {}
    for key in ('sync.server.url', 'sync.server.client_id', 'sync.encryption_secret'):
        try:
            value = run('task', '_get', 'rc.' + key).decode().strip()
        except UnicodeDecodeError:
            raise RuntimeError('TaskChampion sync setting invalid') from None
        if not value or '\n' in value or '\r' in value:
            raise RuntimeError('TaskChampion sync setting missing or invalid')
        settings[key] = value
    taskdata = tmp / 'taskdata'
    taskdata.mkdir(mode=0o700)
    taskrc = tmp / 'taskrc'
    with os.fdopen(os.open(taskrc, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as f:
        for key, value in settings.items():
            f.write(f'{key}={value}\n')
    env = os.environ.copy()
    env.update(TASKRC=str(taskrc), TASKDATA=str(taskdata))
    def task_run(*args, scratch=False):
        result = subprocess.run(('task', 'rc.hooks=off', *args), env=env if scratch else None,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=300)
        if result.returncode:
            raise RuntimeError('task command failed')
        return result.stdout
    def count(scratch):
        total = 0
        for status in ('pending', 'completed'):
            result = task_run('rc.context=', 'status:' + status, 'count', scratch=scratch).strip()
            if not result.isdigit():
                raise RuntimeError('invalid task count')
            total += int(result)
        return total
    task_run('sync', scratch=True)
    restored, live = count(True), count(False)
    delta = int(os.getenv('BACKUP_DRILL_TASK_DELTA', '5'))
    if delta < 0 or abs(restored - live) > delta:
        raise RuntimeError(f'task count differs: restored {restored}, live {live}, limit {delta}')
    return f'restored {restored} tasks from the server, live {live}'

checks = {'restic': restic_check, 'home': lambda: mirror_check('home'), 'dev': lambda: mirror_check('dev'), 'task': task_check, 'system': system_check, 'taskchampion': server_check}
try:
    data = json.loads(state.read_text())
except (OSError, ValueError):
    data = {}
data.setdefault('layers', {})
failed = False
for name in selected:
    start = time.monotonic()
    try:
        detail = checks[name]()
        ok = True
    except Exception as exc:
        detail = str(exc)
        ok = False
        failed = True
    seconds = round(time.monotonic() - start, 2)
    previous = data['layers'].get(name, {})
    last_run = int(time.time())
    last_success = last_run if ok else previous.get('last_success', previous.get('last_run', 0) if previous.get('ok') is True else 0)
    data['layers'][name] = {'ok': ok, 'detail': detail, 'seconds': seconds, 'last_run': last_run, 'last_success': last_success}
    print(f"{name}: {'ok' if ok else 'FAIL'}: {detail} ({seconds}s)", file=sys.stdout if ok else sys.stderr, flush=True)
data['last_run'] = int(time.time())
state.parent.mkdir(parents=True, exist_ok=True)
# Replacing a unique file in the same directory makes the result atomic.
import tempfile
with tempfile.NamedTemporaryFile(mode='w', dir=state.parent, prefix='.drill-', delete=False) as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.replace(f.name, state)
sys.exit(1 if failed else 0)
PY
