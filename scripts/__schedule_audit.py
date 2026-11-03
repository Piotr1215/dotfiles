#!/usr/bin/env python3
"""Reject crontab entries that can run more often than every five minutes."""
import sys

# Add a narrowly identified exception here only with a reason and review date.
ALLOWLIST = {}


def minutes(field):
    result = set()
    for part in field.split(','):
        base, sep, step = part.partition('/')
        stride = int(step) if sep else 1
        if stride < 1:
            raise ValueError('invalid step')
        if base == '*':
            start, end = 0, 59
        elif '-' in base:
            start, end = map(int, base.split('-', 1))
        else:
            start = int(base)
            end = 59 if sep else start
        if start < 0 or end > 59 or start > end:
            raise ValueError('invalid minute range')
        result.update(range(start, end + 1, stride))
    return sorted(result)


def audit(lines):
    errors = []
    for n, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith('#') or ('=' in line.split()[0] and not line.startswith('@')):
            continue
        if any(token in line for token in ALLOWLIST):
            continue
        fields = line.split()
        if line.startswith('@'):
            if fields[0] not in ('@reboot', '@yearly', '@annually', '@monthly', '@weekly', '@daily', '@midnight', '@hourly'):
                errors.append(f'{n}: unknown or frequent schedule: {line}')
            continue
        if len(fields) < 6:
            errors.append(f'{n}: invalid cron entry: {line}')
            continue
        try:
            values = minutes(fields[0])
            gaps = [b-a for a, b in zip(values, values[1:] + [values[0]+60])]
            if min(gaps) < 5:
                errors.append(f'{n}: schedule can run less than five minutes apart: {line}')
        except (ValueError, IndexError):
            errors.append(f'{n}: invalid minute field: {line}')
    return errors


if __name__ == '__main__':
    failures = audit(sys.stdin)
    print('\n'.join(failures), file=sys.stderr if failures else sys.stdout, end='\n' if failures else '')
    sys.exit(bool(failures))
