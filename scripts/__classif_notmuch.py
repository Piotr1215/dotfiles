#!/usr/bin/env python3
"""Tag recent notmuch mail with classif verdicts (notmuch's post-new hook).

    __classif_notmuch.py email-bulk=bulk email-action=action [--query Q] [--limit N] [--budget S]

Each argument is spec=tag. classif is the library: this script loads the
`classif` command found on PATH and calls its spec, host and log functions.
Exits 0 on every path: notmuch new must never fail on it.
"""
import argparse
import importlib.machinery
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time

MAIL_QUERY = ("tag:inbox AND date:7d.. AND NOT tag:classif/scored "
              "AND NOT (tag:spam OR tag:newsletter OR tag:talks)")
_HTML_TAG = re.compile(r"<[^>]+>")


# The classif command, found on PATH like any other tool.
def _load_classif():
    path = shutil.which("classif")
    if not path:
        raise ImportError("classif not on PATH")
    loader = importlib.machinery.SourceFileLoader("classif", os.path.realpath(path))
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("classif", loader))
    loader.exec_module(mod)
    return mod


def mail_text(parts):
    """The first text/plain body in a notmuch part tree, else the first
    text/html with its tags stripped."""
    found = {"text/plain": [], "text/html": []}

    def walk(ps):
        for p in ps:
            c = p.get("content")
            if isinstance(c, list):
                walk(c)
            elif isinstance(c, str) and p.get("content-type") in found:
                found[p["content-type"]].append(c)
    walk(parts)
    if found["text/plain"]:
        return found["text/plain"][0]
    return " ".join(_HTML_TAG.sub(" ", found["text/html"][0]).split()) if found["text/html"] else ""


def _notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, timeout=60, check=True).stdout


def _shown(node):
    """The one message `notmuch show --entire-thread=false` fills in. A
    thread root comes back as [[[msg, []]]]; a reply sits under a null for
    each ancestor, [[[null, [[msg, []]]]]]."""
    if isinstance(node, dict):
        return node
    for child in node or []:
        found = _shown(child)
        if found:
            return found
    return None


def mail(*argv):
    """Each positional is spec=tag. A spec that says yes (or, once it has a
    threshold, reaches it) tags the mail classif/<tag>, and an answer under
    the spec's min_p tags it classif/<tag>-unsure instead; a mail every spec
    answered gets classif/scored and leaves the query. Mail a host could not
    score stays for the next run. Always 0: notmuch new must never fail on it."""
    ap = argparse.ArgumentParser(prog="__classif_notmuch.py")
    ap.add_argument("pairs", nargs="+", metavar="SPEC=TAG")
    ap.add_argument("--query", default=MAIL_QUERY)
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--budget", type=float, default=120.0)
    a = ap.parse_args(argv)
    try:
        sf = _load_classif()
    except ImportError as e:
        print(f"classif-notmuch: {e}", file=sys.stderr)
        return 0
    if sf.off():
        return 0
    deadline = time.monotonic() + a.budget
    try:
        specs = [(n, t, sf.load_spec(n)) for n, t in (p.split("=", 1) for p in a.pairs)]
        ids = json.loads(_notmuch("search", "--format=json", "--output=messages", "--sort=newest-first",
                                  f"--limit={a.limit}", a.query))
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        print(f"classif-notmuch: {e}", file=sys.stderr)
        return 0
    host = sf.pick(specs[0][2]) if specs else None
    if not host:
        print(f"classif-notmuch: {sf.no_host()}", file=sys.stderr)
        return 0
    done = tagged = 0
    for mid in ids:
        if time.monotonic() > deadline:
            break
        qid = 'id:"' + mid.replace('"', '""') + '"'
        try:
            msg = _shown(json.loads(_notmuch("show", "--format=json", "--body=true", "--entire-thread=false",
                                             "--include-html", qid)))
        except (OSError, ValueError, subprocess.SubprocessError) as e:
            print(f"classif-notmuch: {mid}: {e}", file=sys.stderr)
            continue
        if not msg:
            print(f"classif-notmuch: {mid}: notmuch show returned no message", file=sys.stderr)
            continue
        h = msg.get("headers", {})
        subject = h.get("Subject") or "(no subject)"
        fields = {"from": h.get("From") or "unknown", "subject": subject,
                  "body": mail_text(msg.get("body", [])) or subject}
        meta = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "session": "", "hook": "notmuch",
                "channel": "mail"}
        tags, rows, answered = [], [], True
        for name, tag, spec in specs:
            r = sf.judge_item(spec, fields, host)
            d = sf.decide(spec, r)
            rows.append(sf.make_row(name, spec, host, meta, subject, {"id": mid[:200]}, r, d))
            if r["label"] is None:
                answered = answered and "mass" in r
            elif d == "unsure":
                tags.append(f"+classif/{tag}-unsure")
            elif (d == "drop") if spec.get("threshold") else r["label"] == "yes":
                tags.append(f"+classif/{tag}")
        sf.append(rows)
        if not answered:
            continue
        try:
            _notmuch("tag", *tags, "+classif/scored", "--", qid)
        except (OSError, subprocess.SubprocessError) as e:
            print(f"classif-notmuch: tag {mid}: {e}", file=sys.stderr)
            continue
        done += 1
        tagged += bool(tags)
    print(f"classif-notmuch: {done} of {len(ids)} scored, {tagged} tagged")
    return 0


if __name__ == "__main__":
    sys.exit(mail(*sys.argv[1:]))
