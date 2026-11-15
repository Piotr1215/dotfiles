#!/usr/bin/env python3
"""Render the CI infrastructure project view from the existing project gather."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone

HERE = Path(__file__).resolve().parent

def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

ci = load('ci_status', '__ci_project_status.py')
page = load('project_page', '__project_page.py')
HOME = Path.home()
OUT = HOME / '.local/state/project-views/ci-infra.md'
CACHE = HOME / '.local/state/project-views/ci-infra-sections.json'
DONE_CACHE = HOME / '.local/state/project-views/ci-infra-done.json'
PAGE = HOME / '.local/state/project-pages/ci-infra.json'
EVENTS = HOME / '.local/state/notifications.log'
WATCH = HOME / '.claude/data/pr-watermarks.json'
URL = re.compile(r'https?://[^\s<>]+')


def atomic_write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, tmp = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(value)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def read_json(path):
    return json.loads(path.read_text())


def command(args, timeout=60):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=timeout).stdout


def task_export():
    return json.loads(command(['task', 'rc.context=none', 'rc.hooks=off', 'rc.verbose=nothing', 'status:pending', 'export']))


def finished(data, now):
    cutoff = now - timedelta(days=30)
    rows = []
    for issue in data['project']['issues']:
        moment = ci.parse_time(issue.get('completedAt'))
        if issue['state']['type'] == 'completed' and moment and moment >= cutoff:
            milestone = (issue.get('projectMilestone') or {}).get('name')
            rows.append({'id': issue['identifier'], 'title': issue['title'], 'completed_at': moment.isoformat(),
                         'kind': 'issue', 'milestone': milestone})
    for url, pr in data['prs'].items():
        moment = ci.parse_time(pr.get('mergedAt'))
        ident = ci.pr_id(url)
        if ident and pr.get('state', '').upper() == 'MERGED' and moment and moment >= cutoff:
            rows.append({'id': ident, 'title': pr['title'], 'completed_at': moment.isoformat(), 'kind': 'merged PR'})
    return sorted(rows, key=lambda x: x['completed_at'], reverse=True)


def build_done(data, now, summarizer=None):
    candidates = finished(data, now)
    lines = summarizer(candidates) if summarizer else ci.completed_summary(candidates, cache=DONE_CACHE)
    links = {i['identifier']: i['url'] for i in data['project']['issues']}
    links.update({ci.pr_id(url): url for url in data['prs']})
    result = []
    for line in lines:
        ids = ci.ID.findall(line)
        ident = ids[0]
        result.append('- ' + ci.fact_text(line) + f' [{ident}]({links[ident]})')
    return '\n'.join(result)


def refs(data):
    result = {i['identifier'] for i in data['project']['issues']}
    result.update(filter(None, (ci.pr_id(url) for url in data['prs'])))
    return result


def matches(task, data):
    if task.get('project') == ci.PROJECT:
        return True
    contents = ' '.join([str(task.get('linear_issue_id', ''))] + [
        x.get('description', '') for x in task.get('annotations', [])
        if re.match(r'^(link|target):', x.get('description', ''), re.I)]).lower()
    return any(re.search(r'(?<![\w-])' + re.escape(ref.lower()) + r'(?![\w-])', contents) for ref in refs(data))


def session_lines(tasks, data, sessions):
    result = []
    for task in tasks:
        if task.get('project') != ci.PROJECT:
            continue
        annotations = '\n'.join(x.get('description', '') for x in task.get('annotations', []))
        for name in sessions:
            if re.search(r'\btmux session\s+' + re.escape(name) + r'\b', annotations):
                result.append(f'- Agent {name}: {task.get("description", "")} [project]({data["project"]["url"]})')
    return result


def slack_lines(data, text, now):
    ids = refs(data)
    result = {}
    for line in text.splitlines():
        fields = line.split('\t')
        if len(fields) < 4 or fields[1] not in ('slack', 'slack-self'):
            continue
        try:
            stamp = datetime.strptime(fields[0], '%Y-%m-%d %H:%M:%S').astimezone()
        except ValueError:
            continue
        if stamp < now - timedelta(hours=48):
            continue
        if '#proj-ci-infra' not in line.lower() and not any(re.search(r'(?<![\w-])' + re.escape(ref) + r'(?![\w-])', line, re.I) for ref in ids):
            continue
        found = re.search(r'link:(https://\S+)', line)
        if found:
            result[found.group(1)] = f'- Slack: {fields[2].strip()} [thread]({found.group(1)})'
    return list(result.values())


def build_now(data, tasks, sessions, events, now):
    lines = []
    for issue in data['project']['issues']:
        if issue['state']['type'] == 'started':
            lines.append(f'- {issue["identifier"]}: {issue["title"]} [issue]({issue["url"]})')
    for url, pr in data['prs'].items():
        if pr.get('state', '').upper() == 'OPEN':
            lines.append(f'- {ci.pr_id(url)}: {pr["title"]}, CI {page.ci(pr)} [PR]({url})')
    lines += session_lines(tasks, data, sessions)
    lines += slack_lines(data, events, now)
    return '\n'.join(lines) if lines else '- No current activity found in the available sources.'


def annotation(task, key):
    prefix = key + ':'
    values = [x.get('description', '')[len(prefix):].strip() for x in task.get('annotations', [])
              if x.get('description', '').lower().startswith(prefix)]
    return values[-1] if values else ''


def build_next(data, tasks, reviews, watched):
    selected = [t for t in tasks if t.get('status') == 'pending' and 'piotr' in t.get('tags', []) and matches(t, data)]
    selected.sort(key=lambda t: (dict(H=0, M=1, L=2).get(t.get('priority'), 3), ''.join(chr(255-ord(c)) for c in t.get('entry', '') if ord(c)<256)))
    items = []
    for task in selected:
        step = annotation(task, 'piotr-step') or annotation(task, 'what') or task.get('description', '')
        item = step
        for key in ('link', 'cmd', 'target'):
            value = annotation(task, key)
            if value:
                item += f'\n   {key}: {value}'
        if 'draft' in task.get('tags', []):
            draft = annotation(task, 'draft') or annotation(task, 'brief')
            if draft:
                item += '\n\n   ```text\n' + '\n'.join('   '+line for line in draft.splitlines()) + '\n   ```'
        items.append(item)
    seen = set()
    for pr in reviews + watched:
        if pr['url'] in seen:
            continue
        seen.add(pr['url'])
        items.append(f'{pr.get("title", "Review watched PR")} [PR]({pr["url"]})')
    return '\n'.join(f'{n}. {item}' for n, item in enumerate(items, 1)) or 'No pending steps found in the available sources.'


def read_reviews(data):
    repos = {'/'.join(url.split('/')[3:5]) for url in data['prs']}
    login = data['github_login']
    query = ['gh', 'search', 'prs', '--review-requested', login, '--state', 'open', '--limit', '100', '--json', 'url,title,updatedAt']
    rows = json.loads(command(query))
    return sorted((r for r in rows if '/'.join(r['url'].split('/')[3:5]) in repos), key=lambda r: r.get('updatedAt', ''), reverse=True)


def read_watch(data):
    state = read_json(WATCH)
    repos = {'/'.join(url.split('/')[3:5]) for url in data['prs']}
    urls = [k for k in state if k.startswith('https://github.com/') and '/'.join(k.split('/')[3:5]) in repos]
    result = []
    for url in urls:
        pr = json.loads(command(['gh', 'pr', 'view', url, '--json', 'url,title,state,mergedAt,updatedAt']))
        if pr['state'] == 'OPEN':
            result.append(pr)
    return sorted(result, key=lambda pr: pr.get('updatedAt', ''), reverse=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('slug', choices=['ci-infra'])
    parser.parse_args()
    now = datetime.now(timezone.utc)
    try:
        old = read_json(CACHE)
    except (OSError, ValueError):
        old = {}
    sections = {}
    errors = []
    try:
        data = read_json(PAGE)
        gathered = ci.parse_time(data['generated_at'])
        if not gathered or now - gathered > timedelta(minutes=25):
            raise ValueError('project gather is older than 25 minutes')
    except Exception as exc:
        data = None
        errors.append(f'project gather: {exc}')
    try:
        tasks = task_export()
    except Exception as exc:
        tasks = None
        errors.append(f'tasks: {exc}')
    def build(name, fn):
        try:
            content = fn()
            sections[name] = {'text': content, 'at': now.isoformat()}
        except Exception as exc:
            errors.append(f'{name}: {exc}')
            if name in old:
                sections[name] = old[name]
            else:
                sections[name] = {'text': 'Unavailable; no previous good section.', 'at': now.isoformat()}
            sections[name] = {**sections[name], 'stale': True}
    def need(value, label):
        if value is None:
            raise ValueError(label + ' unavailable')
        return value
    build('Done', lambda: build_done(need(data, 'project'), now))
    build('Now', lambda: build_now(need(data, 'project'), need(tasks, 'tasks'), command(['tmux', 'list-sessions', '-F', '#{session_name}']).splitlines(), EVENTS.read_text(errors='replace'), now))
    build('Next for you', lambda: build_next(need(data, 'project'), need(tasks, 'tasks'), read_reviews(data), read_watch(data)))
    title = data['project']['name'] if data else 'CI infrastructure improvements'
    project_url = data['project']['url'] if data else 'https://linear.app/loft/project/ci-infrastructure-improvements-f4a56eb77a87'
    output = f'# {title}\n\n[Linear project]({project_url}) · updated {now.astimezone():%H:%M}\n'
    for name, section in sections.items():
        suffix = f' (stale since {ci.parse_time(section["at"]).astimezone():%H:%M})' if section.get('stale') else ''
        output += f'\n## {name}{suffix}\n\n{section["text"]}\n'
    atomic_write(OUT, output)
    atomic_write(CACHE, json.dumps(sections, ensure_ascii=False, indent=2) + '\n')
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0

if __name__ == '__main__':
    sys.exit(main())
