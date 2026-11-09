#!/usr/bin/env python3
"""Send handoff brief edits to Taskwarrior and triage."""
import difflib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid as uuidlib

UUID_RE = re.compile(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')


def brief_paths(uid):
    state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state')))
    folder = state / 'taskwarrior' / 'briefs' / uid
    return folder / 'brief.md', folder / '.piotr-baseline.md', folder / '.piotr-pending-save.json'


def atomic_json(path, value):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value))
    temp.replace(path)


def comments_section(text):
    """Return the body of the user's editable My comments section only."""
    lines = []
    fence = ''
    for line in text.splitlines():
        marker = re.match(r'^ {0,3}(`{3,}|~{3,})(.*)$', line)
        fenced = bool(fence)
        if marker:
            token, suffix = marker.groups()
            if not fence:
                fence, fenced = token, True
            elif token[0] == fence[0] and len(token) >= len(fence) and not suffix.strip():
                fence = ''
        lines.append((line, fenced))
    start = next((index for index, (line, fenced) in enumerate(lines)
                  if not fenced and line.lower().strip() == '## my comments'), None)
    if start is None:
        return ''
    end = next((index for index in range(start + 1, len(lines))
                if not lines[index][1] and lines[index][0].startswith('## ')), len(lines))
    return '\n'.join(line for line, _ in lines[start + 1:end]).strip('\n')


def init(uid):
    """Seed an immutable comparison point once, before Piotr starts editing."""
    brief, baseline, _ = brief_paths(uid)
    if not brief.is_file():
        raise FileNotFoundError(brief)
    if not baseline.exists():
        temp = baseline.with_suffix('.tmp')
        temp.write_text(brief.read_text())
        temp.replace(baseline)


def changed_lines(before, after):
    old_lines, new_lines = before.splitlines(), after.splitlines()
    lines = []
    matcher = difflib.SequenceMatcher(a=old_lines, b=new_lines, autojunk=False)
    for tag, old_start, old_end, new_start, new_end in matcher.get_opcodes():
        if tag in ('replace', 'delete'):
            lines.extend('-' + line for line in old_lines[old_start:old_end])
        if tag in ('replace', 'insert'):
            lines.extend('+' + line for line in new_lines[new_start:new_end])
    return '\n'.join(lines).strip()


def export_task(uid):
    command = os.environ.get('HANDOFF_TASK_COMMAND', 'task')
    result = subprocess.run(
        [command, 'rc.context=none', 'rc.hooks=off', 'rc.verbose=nothing',
         'rc.gc=off', uid, 'export'], check=True, capture_output=True,
        text=True, timeout=10,
    )
    rows = json.loads(result.stdout)
    return next(row for row in rows if row.get('uuid') == uid)


def save(uid):
    brief, baseline, pending_path = brief_paths(uid)
    if not brief.is_file() or not baseline.is_file():
        raise FileNotFoundError('brief or its save baseline is missing')
    delivered = False
    while True:
        pending = json.loads(pending_path.read_text()) if pending_path.exists() else None
        if pending is None:
            current = brief.read_text()
            change = changed_lines(comments_section(baseline.read_text()), comments_section(current))
            if not change:
                temp = baseline.with_suffix('.tmp')
                temp.write_text(current)
                temp.replace(baseline)
                return delivered
            pending = {'id': str(uuidlib.uuid4()), 'after': current, 'change': change}
            atomic_json(pending_path, pending)
        change, current, event_id = pending['change'], pending['after'], pending['id']

        # The unique event marker lets a retry avoid duplicating a Taskwarrior annotation.
        annotation = f'piotr-comment: {change}\n[brief-save:{event_id}]'
        task = export_task(uid)
        notes = [row.get('description', '') for row in task.get('annotations', [])]
        tw = os.environ.get('HANDOFF_TW_WRAPPER', str(Path.home() / '.claude/scripts/__tw.sh'))
        if not any(f'[brief-save:{event_id}]' in note for note in notes):
            subprocess.run([tw, 'note', uid, annotation], check=True, timeout=20)

        quoted = '\n'.join('> ' + line for line in change.splitlines())
        title = ' '.join(str(task.get('description', '')).split())
        # Triage reads every comment; the wording tells a handoff from a regular task.
        kind = 'changed handoff' if 'piotr' in task.get('tags', []) else 'commented on task'
        message = f'Piotr {kind} {uid} {title}:\n{quoted}'
        sender = os.environ.get('HANDOFF_SND_COMMAND', str(Path.home() / '.claude/scripts/snd'))
        env = dict(os.environ, SND_FROM='handoffs-file')
        subprocess.run([sender, '--no-human', '-t', 'triage', message],
                       check=True, timeout=20, env=env)

        temp = baseline.with_suffix('.tmp')
        temp.write_text(current)
        temp.replace(baseline)
        pending_path.unlink(missing_ok=True)
        delivered = True


def main(argv):
    if len(argv) != 3 or argv[1] not in {'init', 'save'} or not UUID_RE.fullmatch(argv[2]):
        print('usage: __handoff_brief_save.py init|save <task-uuid>', file=sys.stderr)
        return 2
    try:
        init(argv[2]) if argv[1] == 'init' else save(argv[2])
    except (OSError, ValueError, StopIteration, subprocess.SubprocessError) as error:
        print(f'Could not save handoff brief: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
