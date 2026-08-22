#!/usr/bin/env python3
"""Next-run times for cron expressions, one batch per invocation.

Reads one cron expression per line on stdin, writes one compact "time until
next run" per line on stdout, in the same order. Batched deliberately: the
argos widget asks about every registered job each refresh, and paying python
startup once beats paying it per job.

No croniter dependency; the subset of cron syntax that appears in a crontab
(*, */step, a,b,c lists, m-n ranges, names for month and weekday) is small
enough to match directly.
"""
import sys
from datetime import datetime, timedelta

DOW = {"sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4,
       "fri": 5, "sat": 6}
MON = {"jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
       "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12}

# @reboot has no next time that can be computed from the clock.
SPECIAL = {
    "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *",
    "@monthly": "0 0 1 * *", "@weekly": "0 0 * * 0",
    "@daily": "0 0 * * *", "@midnight": "0 0 * * *",
    "@hourly": "0 * * * *",
}


def parse_field(spec, lo, hi, names=None):
    """Expand one cron field into the set of values it matches."""
    values = set()
    for part in spec.split(","):
        step = 1
        if "/" in part:
            part, _, step_s = part.partition("/")
            step = int(step_s)
        if part in ("*", ""):
            start, end = lo, hi
        elif "-" in part.strip("-") or (part.count("-") == 1 and not part.startswith("-")):
            a, _, b = part.partition("-")
            start, end = _named(a, names), _named(b, names)
        else:
            start = end = _named(part, names)
        for v in range(start, end + 1, step):
            values.add(v)
    return values


def _named(token, names):
    token = token.strip().lower()
    if names and token in names:
        return names[token]
    return int(token)


def next_run(expr, now):
    expr = expr.strip()
    if expr.startswith("@"):
        if expr == "@reboot":
            return None
        expr = SPECIAL.get(expr, expr)
        if expr.startswith("@"):
            return None

    fields = expr.split()
    if len(fields) < 5:
        return None
    minute, hour, dom, mon, dow = fields[:5]

    try:
        minutes = parse_field(minute, 0, 59)
        hours = parse_field(hour, 0, 23)
        doms = parse_field(dom, 1, 31)
        mons = parse_field(mon, 1, 12, MON)
        dows = {d % 7 for d in parse_field(dow, 0, 7, DOW)}
    except (ValueError, KeyError):
        return None

    # Restricted day-of-month and day-of-week are OR'd, per cron semantics.
    dom_restricted = dom.strip() != "*"
    dow_restricted = dow.strip() != "*"

    t = (now + timedelta(minutes=1)).replace(second=0, microsecond=0)
    # Four years covers the worst realistic case (Feb 29 on a weekday rule).
    limit = t + timedelta(days=366 * 4)
    while t < limit:
        if t.month not in mons:
            # Skip to the first of the next month rather than minute-stepping.
            t = (t.replace(day=1) + timedelta(days=32)).replace(
                day=1, hour=0, minute=0)
            continue
        day_ok_dom = t.day in doms
        day_ok_dow = (t.weekday() + 1) % 7 in dows
        if dom_restricted and dow_restricted:
            day_ok = day_ok_dom or day_ok_dow
        elif dom_restricted:
            day_ok = day_ok_dom
        elif dow_restricted:
            day_ok = day_ok_dow
        else:
            day_ok = True
        if not day_ok:
            t = (t + timedelta(days=1)).replace(hour=0, minute=0)
            continue
        if t.hour not in hours:
            t = (t + timedelta(hours=1)).replace(minute=0)
            continue
        if t.minute not in minutes:
            t += timedelta(minutes=1)
            continue
        return t
    return None


def humanize(delta):
    secs = int(delta.total_seconds())
    if secs < 60:
        return "<1m"
    if secs < 3600:
        return f"{secs // 60}m"
    if secs < 86400:
        return f"{secs // 3600}h"
    return f"{secs // 86400}d"


def main():
    now = datetime.now()
    for line in sys.stdin:
        expr = line.rstrip("\n")
        if not expr.strip():
            print("-")
            continue
        nxt = next_run(expr, now)
        print(humanize(nxt - now) if nxt else "-")


if __name__ == "__main__":
    main()
