#!/usr/bin/env python3
"""Resolve a brief and seed new annotation drafts without discarding saved edits."""
from datetime import datetime, timezone
import hashlib
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

OPEN_START = '<!-- begin open -->'
OPEN_END = '<!-- end open -->'
DETAILS_FILE = '.task-details.md'


def task_time(value):
    """Show a Taskwarrior UTC stamp in local time, or none when unset."""
    if not value:
        return 'none'
    try:
        stamp = datetime.strptime(value, '%Y%m%dT%H%M%SZ').replace(tzinfo=timezone.utc)
    except ValueError:
        return value
    return stamp.astimezone().strftime('%Y-%m-%d %H:%M')


def detail_lines(text):
    """Indent continuation lines and escape any the brief parsers read as structure.

    An unclosed fence or a "## My comments" line inside an annotation would
    otherwise move where the editable comments section starts.
    """
    rows = str(text).splitlines() or ['']
    out = [rows[0]]
    for row in rows[1:]:
        stripped = row.lstrip()
        if stripped.startswith(('```', '~~~')) or stripped.lower().rstrip() == '## my comments':
            row = row[:len(row) - len(stripped)] + '\\' + stripped
        out.append('  ' + row if row.strip() else '')
    return out


def task_details(task):
    """Render a regular task's fields and annotations for the brief pane."""
    tags = ', '.join(task.get('tags', [])) or 'none'
    lines = ['## Task', '']
    for label, value in (('Description', task.get('description', '')),
                         ('Project', task.get('project') or 'none'),
                         ('Tags', tags),
                         ('Status', task.get('status') or 'none'),
                         ('Due', task_time(task.get('due'))),
                         ('Scheduled', task_time(task.get('scheduled')))):
        first, *rest = detail_lines(value)
        lines.append(f'- {label}: {first}')
        lines.extend(rest)
    annotations = sorted(task.get('annotations', []), key=lambda row: row.get('entry', ''))
    lines.extend(('', '### Annotations', ''))
    if not annotations:
        lines.append('none')
    for row in annotations:
        first, *rest = detail_lines(row.get('description', ''))
        lines.append(f'- {task_time(row.get("entry"))} {first}')
        lines.extend(rest)
    return '\n'.join(lines) + '\n'


def write_details(folder, task):
    """Keep the pane's details sidecar current; handoff rows keep their brief as is.

    Nobody edits the sidecar, so it is refreshed even while the editor holds
    the brief lock. The editor splices it into the open buffer.
    """
    sidecar = folder / DETAILS_FILE
    if 'piotr' in task.get('tags', []):
        sidecar.unlink(missing_ok=True)
        return
    temp = sidecar.with_suffix('.tmp')
    temp.write_text(task_details(task))
    temp.replace(sidecar)


def open_urls(task):
    """Return the target permalink followed by explicit link annotations."""
    navigate_path = Path(__file__).with_name('__handoff_navigate.py')
    spec = importlib.util.spec_from_file_location('handoff_navigate', navigate_path)
    navigate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(navigate)
    annotations = sorted(task.get('annotations', []), key=lambda row: row.get('entry', ''))
    target_rows = [row for row in annotations
                   if re.match(r'^\s*target:\s*\S', row.get('description', ''), flags=re.I)]
    urls = []
    if target_rows:
        # Reuse navigation's Slack stamp conversion and URL validation.
        try:
            urls.append(navigate.destination({
                'uuid': task.get('uuid'), 'tags': ['piotr'], 'annotations': [target_rows[-1]],
            }))
        except ValueError as error:
            report_invalid_url(error)
    for row in annotations:
        match = re.match(r'^\s*link:\s*(.*)$', row.get('description', ''), flags=re.I)
        if match:
            try:
                urls.append(navigate.single_url(match.group(1)))
            except ValueError as error:
                report_invalid_url(error)
    return [url for url in urls if url]


def report_invalid_url(error):
    message = f'Could not open handoff destination: {error}'
    # No desktop popup: this runs on every brief refresh and flooded Piotr (6 Nov).
    print(message, file=sys.stderr)


def marked_block(text, start_marker, end_marker, markdown_lines):
    """Find a marker pair outside Markdown fences and return its range and body."""
    rows = text.splitlines(keepends=True)
    states = [fenced for _, fenced in markdown_lines(text)]
    offsets = []
    offset = 0
    for row in rows:
        offsets.append(offset)
        offset += len(row)
    start = next((i for i, row in enumerate(rows)
                  if not states[i] and row.rstrip('\r\n') == start_marker), None)
    if start is None:
        return None
    end = next((i for i in range(start + 1, len(rows))
                if not states[i] and rows[i].rstrip('\r\n') == end_marker), None)
    if end is None:
        return None
    body_start = offsets[start] + len(rows[start])
    body_end = offsets[end]
    body = text[body_start:body_end].strip('\r\n')
    block_end = offsets[end] + len(rows[end].rstrip('\r\n'))
    return offsets[start], block_end, body


def prepare(uid):
    """Keep the canonical brief path and only refresh a newly changed draft."""
    helper = Path(os.environ.get(
        'HANDOFF_BRIEF_RENDERER', str(Path.home() / '.claude/scripts/__tw_brief.py')))
    spec = importlib.util.spec_from_file_location('tw_brief', helper)
    brief = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(brief)
    command = os.environ.get('HANDOFF_TASK_COMMAND', 'task')
    result = subprocess.run([command, 'rc.context=none', 'rc.hooks=off',
                             'rc.verbose=nothing', 'rc.gc=off', uid, 'export'],
                            check=True, capture_output=True, text=True, timeout=10)
    rows = json.loads(result.stdout)
    task = next(row for row in rows if row.get('uuid') == uid)
    root = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state')))
    path = root / 'taskwarrior/briefs' / uid / 'brief.md'
    # The project status is a generated view, not an editable handoff brief.
    if task.get('view_key', '').startswith('standing:') and task.get('project') == 'ci-infrastructure-improvements':
        annotations = task.get('annotations', [])
        notes = [a.get('description', '') for a in annotations if a.get('description', '').startswith('brief: ')]
        if notes:
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            status_path = path.parent / 'project-status.md'
            content = notes[-1][len('brief: '):].strip() + '\n'
            if not status_path.exists() or status_path.read_text() != content:
                temp = status_path.with_suffix('.tmp')
                temp.write_text(content)
                temp.replace(status_path)
            print(status_path)
            return
    # The shared helper uses this same canonical trace path. Do not follow an
    # arbitrary task annotation to another local file.
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not path.exists():
        subprocess.run([sys.executable, str(helper), '--uuid', uid],
                       input=result.stdout, text=True, check=True, stdout=subprocess.DEVNULL)
    write_details(path.parent, task)
    lock =(path.parent.parent / '.editor.lock').open('a+')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        (path.parent / '.prepare-pending').touch()
        print(path)
        return
    before = path.read_text()
    baseline = path.parent / '.piotr-baseline.md'
    delivered = baseline.exists() and baseline.read_text() == before
    text = path.read_text()
    open_pattern = re.escape(OPEN_START) + r'\n.*?\n' + re.escape(OPEN_END)
    if not re.search(open_pattern, text, flags=re.S):
        urls = '\n'.join(open_urls(task))
        block = OPEN_START + '\n' + urls + '\n' + OPEN_END
        text = text.rstrip() + '\n\n## Open\n\n' + block + '\n'
        path.write_text(text)
    draft = brief.latest(task, 'draft') if 'draft' in task.get('tags', []) else ''
    if draft:
        marker = path.parent / '.floater-draft-sha256'
        digest = hashlib.sha256(draft.encode()).hexdigest()
        previous = marker.read_text() if marker.exists() else ''
        if digest != previous:
            text = path.read_text()
            match = marked_block(text, brief.DRAFT_START, brief.DRAFT_END, brief.markdown_lines)
            fence_draft = getattr(brief, 'fence_draft', lambda value: value.strip())
            unfence_draft = getattr(brief, 'unfence_draft', lambda value: value.strip())
            fenced_draft = fence_draft(draft)
            block = brief.DRAFT_START + '\n' + fenced_draft + '\n' + brief.DRAFT_END
            if match and unfence_draft(match[2]) != draft.strip():
                old = unfence_draft(match[2])
                source_drafts = [re.sub(r'^\s*draft:\s*', '', a['description'], flags=re.I).strip()
                                 for a in task.get('annotations', [])
                                 if re.match(r'^\s*draft:', a.get('description', ''), flags=re.I)]
                # Preserve edits even if a newer draft arrived from Gordon.
                if old not in source_drafts:
                    text += '\n## Previous edited draft\n\n' + old + '\n'
                text = text[:match[0]] + block + text[match[1]:]
            elif not match:
                text += '\n## Draft\n\n' + block + '\n'
            if text != path.read_text():
                path.write_text(text)
            marker.write_text(digest)
    if delivered:
        baseline.write_text(path.read_text())
    (path.parent / '.prepare-pending').unlink(missing_ok=True)
    print(path)


if __name__ == '__main__':
    try:
        if sys.argv[1] == '--refresh-pending':
            root = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'taskwarrior/briefs'
            for marker in root.glob('*/.prepare-pending'):
                if re.fullmatch(r'[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', marker.parent.name):
                    prepare(marker.parent.name)
        else:
            prepare(sys.argv[1])
    except (OSError, ValueError, StopIteration, subprocess.SubprocessError) as error:
        print(f'Could not open handoff brief: {error}', file=sys.stderr)
        sys.exit(1)
