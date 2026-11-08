#!/usr/bin/env bash
set -eo pipefail

# The repository and password file are passed by reference to restic.
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/mnt/nas-backup/secure-store}"
export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-$HOME/.config/restic/password}"
python3 - "$@" <<'PY'
import datetime, json, os, pathlib, re, subprocess, sys, tempfile, time

home = pathlib.Path(os.environ['HOME'])
nas = pathlib.Path(os.getenv('BACKUP_ROOT', '/mnt/nas-backup'))
state_dir = home / '.local/state'
now = int(time.time())
names = ['restic', 'home', 'dev', 'task', 'system', 'taskchampion']
if len(sys.argv) > 3 or (len(sys.argv) > 1 and sys.argv[1] != '--prom'):
    print('usage: __backup_status.sh [--prom [file]]', file=sys.stderr)
    sys.exit(2)

# Read optional status files without making absence look like success.
def read(path):
    try:
        return pathlib.Path(path).read_text()
    except OSError:
        return ''

# Parse a log timestamp in the host's local timezone.
def stamp(line):
    match = re.search(r'\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\]', line)
    try:
        return int(time.mktime(time.strptime(match.group(1), '%Y-%m-%d %H:%M:%S'))) if match else 0
    except ValueError:
        return 0

# Read nightly completions together with following component failures and holds.
log = read(os.getenv('BACKUP_LOG', str(home / 'backup.log')))
runs = []
for line in log.splitlines():
    if 'Backup completed in ' in line:
        t = stamp(line)
        if not runs or runs[-1]['time'] != t:
            runs.append({'time': t, 'failed': '', 'hold': False})
    elif runs and 'component(s) failed:' in line:
        runs[-1]['failed'] = line.split('component(s) failed:', 1)[1].strip()
    elif runs and 'Held: restic snapshots done' in line:
        runs[-1]['hold'] = True
clean = [r['time'] for r in runs if not r['failed'] and not r['hold']]
# The producer writes this only after a fully clean, unheld run.
try:
    clean.append(int(read(state_dir / 'backup-last-success').strip()))
except ValueError:
    pass
nightly = max(clean, default=0)
home_success = max([stamp(line) for line in log.splitlines() if 'system files backup completed successfully' in line] or [nightly])
dev_success = max([stamp(line) for line in log.splitlines() if 'dev folder backup completed successfully' in line] or [nightly])
latest = runs[-1] if runs else {'time': 0, 'failed': '', 'hold': False}
hold = (state_dir / 'backup-hold').exists()

try:
    p = subprocess.run(['restic', 'snapshots', '--no-lock', '--json'], capture_output=True, timeout=60, check=True)
    snaps = json.loads(p.stdout)
    task_path = str(home / '.local/share/task-backups')
    snapshots = [x for x in snaps if task_path in [p.rstrip('/') for p in x.get('paths', [])] and 'browser' not in x.get('tags', [])]
    restic_time = max((int(datetime.datetime.fromisoformat(x['time'].replace('Z', '+00:00')).timestamp()) for x in snapshots), default=0)
except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
    restic_time = 0
try:
    task_time = int(read(nas / 'taskwarrior-mirror/.ok-at').strip())
except ValueError:
    task_time = 0
system_lines = read(os.getenv('SYSTEM_BACKUP_LOG', str(state_dir / 'cron-jobs/system-backup-rsync.log'))).splitlines()
system_good = [stamp(line) for line in system_lines if 'SUMMARY: backup complete in' in line]
system_bad = [stamp(line) for line in system_lines if 'SUMMARY: backup FAILED' in line or 'SUMMARY: backup aborted' in line]
system_time = max(system_good, default=0)
try:
    drill = json.loads(read(os.getenv('BACKUP_DRILL_STATE', str(state_dir / 'backup-drill/last.json'))))
    if not isinstance(drill.get('layers'), dict):
        drill = {}
except (ValueError, AttributeError):
    drill = {}
results = drill.get('layers', {})
server = results.get('taskchampion', {})
server_time = server.get('last_success', server.get('last_run', drill.get('last_run', 0)) if server.get('ok') is True else 0)
rows = []
for name, last, max_age in [('restic', restic_time, 26*3600), ('home', home_success, 25*3600), ('dev', dev_success, 25*3600), ('task', task_time, 300), ('system', system_time, 8*86400), ('taskchampion', server_time, 86400)]:
    result = results.get(name, {})
    failure = latest['failed'].lower()
    failed = ((name == 'home' and ('system files' in failure or 'home folder' in failure or 'home backup' in failure)) or
              (name == 'dev' and 'dev folder' in failure) or
              (name == 'restic' and 'restic' in failure) or
              (name == 'system' and max(system_bad, default=0) > system_time))
    if hold and name in ('home', 'dev'):
        status = 'held'
    elif failed:
        status = 'failed'
    elif not last:
        status = 'unknown'
    elif last > now + 300 or now - last > max_age:
        status = 'stale'
    else:
        status = 'ok'
    # A failed drill means the layer is not healthy even if its timestamp is fresh.
    if result.get('ok') is False:
        status = 'failed'
    rows.append((name, int(last), status, result))

# Discover the actual textfile directory only when the running exporter enables it.
try:
    processes = subprocess.run(['pgrep', '-a', 'node_exporter'], capture_output=True, text=True, check=False).stdout
except OSError:
    processes = ''
collector = None
for line in processes.splitlines():
    match = re.search(r'--collector\.textfile\.directory(?:=|\s+)(\S+)', line)
    enabled = '--collector.disable-defaults' not in line or re.search(r'(?:^|\s)--collector\.textfile(?:\s|$)', line)
    if match and enabled and '--no-collector.textfile' not in line:
        collector = match.group(1)
        break
print('node_exporter textfile directory: ' + (collector or 'not enabled; default ' + str(state_dir / 'backup-status/backup.prom')), file=sys.stderr)
if len(sys.argv) > 1:
    target = pathlib.Path(sys.argv[2] if len(sys.argv) == 3 else (pathlib.Path(collector) / 'backup.prom' if collector else state_dir / 'backup-status/backup.prom'))
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=target.parent, prefix='.backup-prom-', delete=False) as f:
        for name, last, status, result in rows:
            f.write(f'backup_layer_last_success_timestamp_seconds{{layer="{name}"}} {last}\n')
            f.write(f'backup_layer_ok{{layer="{name}"}} {int(status == "ok")}\n')
            f.write(f'backup_drill_ok{{layer="{name}"}} {int(result.get("ok") is True)}\n')
        f.write(f'backup_drill_last_run_timestamp_seconds {int(drill.get("last_run", 0))}\n')
        f.write(f'backup_hold_active {int(hold)}\n')
    os.replace(f.name, target)
else:
    print(f'{"layer":13} | {"last success":19} | {"age":8} | {"state":7} | last drill')
    for name, last, status, result in rows:
        when = datetime.datetime.fromtimestamp(last).strftime('%Y-%m-%d %H:%M:%S') if last else '-'
        age = (f'{max(0, now-last)//86400}d{(max(0, now-last)%86400)//3600}h' if now-last >= 86400 else f'{max(0, now-last)//3600}h{(max(0, now-last)%3600)//60}m') if last else '-'
        d = ('ok' if result.get('ok') is True else 'FAIL' if result.get('ok') is False else '-')
        if result.get('last_run'):
            d += ' ' + datetime.datetime.fromtimestamp(result['last_run']).strftime('%Y-%m-%d %H:%M')
        color = {'ok': '\033[32m', 'failed': '\033[31m', 'held': '\033[33m', 'stale': '\033[33m', 'unknown': '\033[33m'}
        shown = color[status] + f'{status:7}' + '\033[0m' if sys.stdout.isatty() else f'{status:7}'
        print(f'{name:13} | {when:19} | {age:8} | {shown} | {d}')
PY
