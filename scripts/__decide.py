#!/usr/bin/env python3
"""Rank candidates on yes/no criteria a local model answers, mark the lines
each top answer rests on, and keep a record of the decision.

A small local model answers one yes/no claim about one text well and a
many-way pick poorly, and classif -e stops at nine options. So classif asks
every candidate every criterion as its own call, and the score is the product
of the p each criterion wants: p(yes) for -y, p(no) for -n. Any number of
candidates and criteria.

A verdict (-e, repeatable, as classif -e: name or name=description) labels
each candidate instead: one classif -e call per candidate, its question -q.
Three described options is the shape classif's evals measured. With no yes/no
criteria the score is p of the first option, so -e "prioritize=...,..." ranks
by how surely each candidate should be prioritized.

  task status:pending export | jq -c '.[] | {name: .description, text: .description}' |
    __decide.py -c goals.md -c notes.md -q "What should happen to this task?" \\
      -e "prioritize=do it this week, it moves a goal or meets a deadline" \\
      -e "defer=worth doing, not now" -e "drop=serves no goal"
  __decide.py -y "Does this step move one of my goals forward?" \\
              -n "Is this step blocked by something not done yet?" -c goals.md < steps.txt
  __decide.py -y "Does this offer pay above market?" -c market.md offers/*.md
  __decide.py -d next-blog

Candidates, the first source that has any: FILE arguments (name: the file
name, text: its contents); lines on stdin, each a JSON object {"name", "text"}
or plain text that is both; the decision file's "candidates" command, which
prints either.

A decision file is NAME.json in $DECIDE_DIR (default ~/.config/decide), or a
path to one:
  {"question": "the decision, kept in the record",
   "candidates": "shell command",
   "criteria": [{"name": "story", "want": "yes", "question": "...",
                 "context": "text", or "context_cmd": "shell command",
                 "when": "shell command; the criterion counts only if it succeeds"}],
   "verdict": {"question": "...", "options": ["name=description", ...],
               "context": "text", or "context_cmd": "shell command"}}
-y and -n add criteria named q1, q2... -c, repeatable, gives every criterion
without a context of its own a context: each a file or the text itself, joined
in order.

Marks: for the top N (-x, default 1, 0 for none) each non-blank line of the
candidate's text, then of each criterion's context, is dropped in turn and the
criterion asked again. Up to three lines per criterion whose removal moves p by
0.005 or more are printed, + for a line that raised the score; for the verdict,
+ for a line that raised p of the label it got. A one-line task's reasons sit
in the goals it was judged against, so context lines are marked too. The marks
come from the same one-call reading as the answer, so they cannot disagree
with it the way classif --why's line-by-line reading can. That is one call per
line, so a text of one line or over 60, and a context over 60, is not marked.

Record: each run writes the criteria with their context, every candidate's
text, every p and the marks to $XDG_STATE_HOME/decide/NAME/DATE.json (NAME is
adhoc without -d) and names the file on stderr. -j prints the record instead
of the report. -k N shows only the top N, to narrow a long list to a few.

Exit 0 when something ranked, 1 when nothing could be, 2 for a usage error.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

MARK_LINES = 60
MARK_MIN = 0.005
MARKS = 3
VERDICT_Q = "What should happen to this?"


def die(msg, code=2):
    print(f"decide: {msg}", file=sys.stderr)
    sys.exit(code)


def sh(cmd):
    """A shell command's output; a failing command ends the run, naming it."""
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, check=False)
    if r.returncode != 0:
        die(f"command failed ({r.returncode}): {cmd}\n{r.stderr.strip()}", 1)
    return r.stdout


def load_decision(ref):
    if ref.endswith(".json") or "/" in ref:
        path = Path(ref)
    else:
        path = Path(os.environ.get("DECIDE_DIR", Path.home() / ".config/decide")) / f"{ref}.json"
    try:
        decision = json.loads(path.read_text())
    except OSError:
        die(f"no decision file {path}")
    except ValueError as e:
        die(f"{path}: {e}")
    decision["name"] = path.stem
    return decision


def read_context(values):
    """-c values joined in order, each a file's contents or the text itself."""
    parts = []
    for v in values:
        parts.append(Path(v).read_text().strip() if os.path.isfile(v) else v.strip())
    return "\n\n".join(p for p in parts if p) or None


def context_of(spec, shared):
    """A criterion's own context, from its command or its text, else the shared one."""
    own = sh(spec["context_cmd"]) if spec.get("context_cmd") else spec.get("context") or ""
    return own.strip() or shared


def criteria_of(decision, adhoc, verdict_q, options, context):
    out = []
    for c in decision.get("criteria", []):
        if not c.get("name") or not c.get("question") or c.get("want") not in ("yes", "no"):
            die(f"a criterion needs a name, a question and want yes or no: {json.dumps(c)}")
        if c.get("when") and subprocess.run(["bash", "-c", c["when"]], check=False).returncode != 0:
            continue
        out.append({"kind": "label", "name": c["name"], "want": c["want"], "question": c["question"],
                    "context": context_of(c, context)})
    for n, (want, question) in enumerate(adhoc, 1):
        out.append({"kind": "label", "name": f"q{n}", "want": want, "question": question, "context": context})
    v = decision.get("verdict") or {}
    if options or v.get("options"):
        out.append({"kind": "enum", "name": "verdict", "question": verdict_q or v.get("question") or VERDICT_Q,
                    "options": options or v["options"], "context": context_of(v, context)})
    return out


def parse_candidates(text):
    out = []
    for line in text.splitlines():
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            obj = None
        if isinstance(obj, dict) and isinstance(obj.get("text"), str):
            out.append({"name": str(obj.get("name") or obj["text"]), "text": obj["text"]})
        else:
            out.append({"name": line.strip(), "text": line.strip()})
    return out


def candidates_of(files, decision):
    if files:
        out = []
        for f in files:
            try:
                out.append({"name": Path(f).name, "text": Path(f).read_text()})
            except OSError as e:
                die(f"{f}: {e.strerror}")
        return out
    if not sys.stdin.isatty():
        got = parse_candidates(sys.stdin.read())
        if got:
            return got
    if decision.get("candidates"):
        return parse_candidates(sh(decision["candidates"]))
    return []


OWN = object()


def ask(text, crit, context_file=OWN):
    """classif's answer for text as (label, p of every label), or None when it
    cannot score. The context is the criterion's own unless a file, or None
    for none, is given. The question goes before any -e, so classif never
    reads it as the tail of an option's description."""
    if context_file is OWN:
        context_file = crit.get("context_file")
    args = ["classif", "-j"] + (["-c", context_file] if context_file else []) + [crit["question"]]
    for o in crit.get("options", []):
        args += ["-e", o]
    r = subprocess.run(args, input=text, capture_output=True, text=True, check=False)
    if r.returncode not in (0, 1):
        return None
    try:
        out = json.loads(r.stdout)
        return out["label"], {k: float(v) for k, v in out["p"].items()}
    except (ValueError, KeyError, TypeError, AttributeError):
        return None


def wanted(crit, answer, label=None):
    """The p a criterion's score uses: p of the label it wants, or for the
    verdict p of the given label, by default the one it chose."""
    got, p = answer
    return p.get(crit["want"] if crit["kind"] == "label" else label or got)


def rank(cands, crits):
    ranked = []
    for c in cands:
        p, verdict = {}, None
        for k in crits:
            a = ask(c["text"], k)
            if a is None or wanted(k, a) is None:
                print(f"decide: classif could not score {c['name']}", file=sys.stderr)
                break
            if k["kind"] == "label":
                p[k["name"]] = wanted(k, a)
            else:
                verdict = {"label": a[0], "p": a[1]}
        else:
            if p:
                score = 1.0
                for v in p.values():
                    score *= v
            else:
                score = next(iter(verdict["p"].values()))
            ranked.append({"name": c["name"], "score": score, "p": p,
                           **({"verdict": verdict} if verdict else {}), "text": c["text"]})
    ranked.sort(key=lambda r: -r["score"])
    return ranked


def mark(row, crits, tmp):
    """Per criterion, the lines whose removal moves its p most, as {from,
    line, delta}: from the candidate's text or the criterion's context, delta
    p with the line minus p without it."""
    idx = nonblank(row["text"])
    text_ok = 1 < len(idx) <= MARK_LINES
    ctx_ok = {k["name"]: bool(k["context"]) and len(nonblank(k["context"])) <= MARK_LINES for k in crits}
    if not text_ok and not any(ctx_ok.values()):
        row["unmarked"] = f"the text has {len(idx)} line{'s' * (len(idx) != 1)} and no context has 1 to {MARK_LINES}"
        return
    row["marks"] = {}
    for k in crits:
        label = row["verdict"]["label"] if k["kind"] == "enum" else None
        full = row["p"][k["name"]] if k["kind"] == "label" else row["verdict"]["p"][label]
        found = []
        for text, context, source, line in variants(row["text"], k["context"], text_ok, ctx_ok[k["name"]]):
            if context is not OWN and context:
                context_file = os.path.join(tmp, "without-line.txt")
                Path(context_file).write_text(context + "\n")
            else:
                context_file = context
            a = ask(text, k, context_file)
            v = wanted(k, a, label) if a else None
            if v is not None and abs(full - v) >= MARK_MIN:
                found.append({"from": source, "line": line, "delta": round(full - v, 4)})
        found.sort(key=lambda m: -abs(m["delta"]))
        row["marks"][k["name"]] = found[:MARKS]


def variants(text, context, text_ok, ctx_ok):
    """Each (text, context, source, line) with one line left out: of the text
    under the criterion's own context (OWN), then of the context, None when
    the context had only that line."""
    lines = text.split("\n")
    if text_ok:
        for i, line in enumerate(lines):
            if line.strip():
                yield "\n".join(lines[:i] + lines[i + 1:]), OWN, "text", line
    if ctx_ok:
        cl = context.split("\n")
        for i, line in enumerate(cl):
            if line.strip():
                yield text, "\n".join(cl[:i] + cl[i + 1:]).strip() or None, "context", line


def nonblank(text):
    return [l for l in text.split("\n") if l.strip()]


def short(s, n=60):
    s = " ".join(s.split())
    return s if len(s) <= n else s[:n - 1] + "…"


def option_names(options):
    return [n.split("=")[0].strip() for o in options for n in (o.split(",") if "=" not in o else [o])]


def report(question, crits, ranked):
    out = [question] if question else []
    w = max(len(k["name"]) for k in crits)
    for k in crits:
        want = f"want {k['want']:<3}" if k["kind"] == "label" else "one of  "
        out.append(f"  {k['name']:<{w}}  {want}  {k['question']}"
                   + (f" ({', '.join(option_names(k['options']))})" if k["kind"] == "enum" else ""))
    out.append("")
    rows = [["score"] + [k["name"] for k in crits] + ["candidate"]]
    for r in ranked:
        cells = [f"{r['p'][k['name']]:.3f}" if k["kind"] == "label"
                 else f"{r['verdict']['label']} {r['verdict']['p'][r['verdict']['label']]:.3f}" for k in crits]
        rows.append([f"{r['score']:.3f}"] + cells + [short(r["name"])])
    widths = [max(len(row[i]) for row in rows) for i in range(len(rows[0]))]
    out += ["  ".join(c.ljust(widths[i]) for i, c in enumerate(row)).rstrip() for row in rows]
    for r in ranked:
        if "unmarked" in r:
            out += ["", f"why {short(r['name'])}: not marked, {r['unmarked']}"]
        elif "marks" in r:
            out += ["", f"why {short(r['name'])}: lines whose removal moves the answer most"]
            for k in crits:
                out.append(f"  {k['name']}" + (f" ({r['verdict']['label']})" if k["kind"] == "enum" else ""))
                marks = r["marks"][k["name"]]
                out += [f"    {m['delta']:+.3f}  {'context: ' if m['from'] == 'context' else ''}{short(m['line'], 100)}"
                        for m in marks] or ["    (no single line moves it)"]
    return "\n".join(out)


def write_record(name, question, crits, ranked):
    base = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "decide" / name
    base.mkdir(parents=True, exist_ok=True)
    now = datetime.now().astimezone()
    path, n = base / f"{now:%Y-%m-%dT%H%M%S}.json", 1
    while path.exists():
        n += 1
        path = base / f"{now:%Y-%m-%dT%H%M%S}-{n}.json"
    record = {"date": now.isoformat(timespec="seconds"), "decision": name, "question": question,
              "criteria": [{k: c[k] for k in ("kind", "name", "want", "options", "question", "context") if k in c}
                           for c in crits],
              "ranking": ranked}
    path.write_text(json.dumps(record, indent=1, ensure_ascii=False) + "\n")
    return path, record


def main(argv=None):
    ap = argparse.ArgumentParser(prog="__decide.py", description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-d", dest="decision", metavar="NAME", help="a decision file: NAME in $DECIDE_DIR, or a path")
    ap.add_argument("-y", dest="adhoc", action="append", default=[], type=lambda q: ("yes", q),
                    metavar="QUESTION", help="a criterion that wants yes")
    ap.add_argument("-n", dest="adhoc", action="append", type=lambda q: ("no", q),
                    metavar="QUESTION", help="a criterion that wants no")
    ap.add_argument("-e", dest="options", action="append", default=[], metavar="OPTION",
                    help="a verdict option, as classif -e: name or name=description; repeatable")
    ap.add_argument("-q", dest="verdict_q", metavar="QUESTION", help=f"the verdict's question (default: {VERDICT_Q})")
    ap.add_argument("-c", dest="context", action="append", default=[], metavar="CONTEXT",
                    help="context for criteria without one: a file or the text itself; repeatable")
    ap.add_argument("-k", dest="top", type=int, metavar="N", help="show only the top N; the record keeps all")
    ap.add_argument("-x", dest="explain", type=int, default=1, metavar="N", help="mark the top N (default 1)")
    ap.add_argument("-j", dest="json", action="store_true", help="print the record instead of the report")
    ap.add_argument("files", nargs="*", metavar="FILE", help="candidates, one per file")
    a = ap.parse_args(argv)

    decision = load_decision(a.decision) if a.decision else {"name": "adhoc"}
    crits = criteria_of(decision, a.adhoc, a.verdict_q, a.options, read_context(a.context))
    if not crits:
        die("no criteria: give -y, -n or -e, or -d with a decision file")
    cands = candidates_of(a.files, decision)
    if not cands:
        die("no candidates: give files, lines on stdin, or a decision with a candidates command", 1)

    with tempfile.TemporaryDirectory(prefix="decide-") as tmp:
        for i, k in enumerate(crits):
            if k["context"]:
                k["context_file"] = os.path.join(tmp, f"context-{i}.txt")
                Path(k["context_file"]).write_text(k["context"] + "\n")
        ranked = rank(cands, crits)
        if not ranked:
            die("nothing could be scored", 1)
        for row in ranked[:max(a.explain, 0)]:
            mark(row, crits, tmp)

    path, record = write_record(decision["name"], decision.get("question"), crits, ranked)
    print(json.dumps(record, indent=1, ensure_ascii=False) if a.json else report(decision.get("question"), crits, ranked[:a.top] if a.top else ranked),
          flush=True)
    print(f"decide: record in {path}", file=sys.stderr)


if __name__ == "__main__":
    main()
