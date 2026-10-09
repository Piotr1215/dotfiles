"""__decide.py ranks candidates on yes/no criteria and a verdict that classif
answers, marks the lines the top answers rest on and records the decision.
These tests run the script against a stub classif whose p(yes) starts at 0.5
and moves by fixed amounts when a word appears in the text or the context, so
every score and mark below is computed by hand."""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).parents[2] / "scripts" / "__decide.py"

# Each rule: when the question holds "q" and the text (or context) holds
# "has", p(yes) moves by "d". A text holding UNSCORED exits 2.
STUB = r'''#!/usr/bin/env python3
import json, os, sys
args, ctx, opts, q, i = sys.argv[1:], "", [], None, 0
while i < len(args):
    a = args[i]
    if a == "-c":
        ctx = open(args[i + 1]).read(); i += 2
    elif a == "-e":
        opts.append(args[i + 1]); i += 2
    elif a == "-j":
        i += 1
    else:
        q = a; i += 1
text = sys.stdin.read()
with open(os.environ["STUB_LOG"], "a") as f:
    f.write(json.dumps({"q": q, "ctx": ctx, "text": text, "opts": opts}) + "\n")
if "UNSCORED" in text:
    sys.exit(2)
y = 0.5
for r in json.loads(os.environ.get("STUB_RULES", "[]")):
    if r["q"] in q and r["has"] in (ctx if r.get("in") == "ctx" else text):
        y += r["d"]
y = round(min(max(y, 0.01), 0.99), 4)
if opts:
    names = [o.split("=")[0] for o in opts]
    p = {n: 0.0 for n in names}
    p[names[0]] = y
    p[names[-1]] = round((1 - y) * 0.7, 4)
    for n in names[1:-1]:
        p[n] = round((1 - y) * 0.3 / (len(names) - 2), 4)
    p["none"] = 0.0
else:
    p = {"yes": y, "no": round(1 - y, 4), "unknown": 0.0}
label = max(p, key=p.get)
print(json.dumps({"label": label, "p": p}))
sys.exit(0 if label == next(iter(p)) else 1)
'''


@pytest.fixture
def env(tmp_path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    stub = bin_dir / "classif"
    stub.write_text(STUB)
    stub.chmod(0o755)
    e = dict(os.environ)
    e.update(PATH=f"{bin_dir}:{e['PATH']}", STUB_LOG=str(tmp_path / "log"),
             XDG_STATE_HOME=str(tmp_path / "state"), DECIDE_DIR=str(tmp_path / "decide"))
    return e


def decide(env, *args, stdin="", rules=()):
    e = dict(env, STUB_RULES=json.dumps(list(rules)))
    return subprocess.run([sys.executable, str(SCRIPT), *args], input=stdin, env=e,
                          capture_output=True, text=True, check=False)


def scores(out):
    """The table's rows below the header, each split into cells."""
    lines = out.splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith("score"))
    rows = []
    for l in lines[start + 1:]:
        if not l.strip():
            break
        rows.append(l.split())
    return rows


def record(env, name="adhoc"):
    (path,) = (Path(env["XDG_STATE_HOME"]) / "decide" / name).glob("*.json")
    return json.loads(path.read_text())


def test_ranks_by_the_product_of_the_p_each_criterion_wants(env):
    r = decide(env, "-y", "Is it fun?", "-n", "Is it far?",
               stdin="fun near\nfun far\ndull near\n",
               rules=[{"q": "fun", "has": "fun", "d": 0.4}, {"q": "far", "has": "far", "d": 0.3}])
    assert r.returncode == 0, r.stderr
    assert "  q1  want yes  Is it fun?" in r.stdout
    assert "  q2  want no   Is it far?" in r.stdout
    # fun near 0.9 * 0.5, dull near 0.5 * 0.5, fun far 0.9 * 0.2
    assert scores(r.stdout) == [["0.450", "0.900", "0.500", "fun", "near"],
                                ["0.250", "0.500", "0.500", "dull", "near"],
                                ["0.180", "0.900", "0.200", "fun", "far"]]


def test_files_are_candidates_and_marks_name_the_line_that_moved_p(env, tmp_path):
    (tmp_path / "a.txt").write_text("fun thing\nboring line\n")
    (tmp_path / "b.txt").write_text("dull\n")
    r = decide(env, "-y", "Is it fun?", str(tmp_path / "a.txt"), str(tmp_path / "b.txt"),
               rules=[{"q": "fun", "has": "fun", "d": 0.4}])
    assert r.returncode == 0, r.stderr
    assert [row[-1] for row in scores(r.stdout)] == ["a.txt", "b.txt"]
    assert "why a.txt: lines whose removal moves the answer most\n  q1\n    +0.400  fun thing\n" in r.stdout
    assert "boring line" not in r.stdout
    assert "why b.txt" not in r.stdout


def test_a_verdict_labels_each_candidate_and_marks_the_context_line_behind_it(env):
    r = decide(env, "-c", "Goal: race in April\nNote: tired", "-q", "What should happen to this task?",
               "-e", "prioritize=do it now", "-e", "defer=later", "-e", "drop=serves no goal",
               stdin="run plan\nshelf\n",
               rules=[{"q": "happen", "has": "run", "d": 0.3},
                      {"q": "happen", "has": "race", "d": 0.15, "in": "ctx"},
                      {"q": "happen", "has": "shelf", "d": -0.4}])
    assert r.returncode == 0, r.stderr
    assert "  verdict  one of    What should happen to this task? (prioritize, defer, drop)" in r.stdout
    # run plan: 0.5 + 0.3 + 0.15 = 0.95; shelf: 0.5 + 0.15 - 0.4 = 0.25, drop at 0.75 * 0.7
    assert scores(r.stdout) == [["0.950", "prioritize", "0.950", "run", "plan"],
                                ["0.250", "drop", "0.525", "shelf"]]
    assert "why run plan: lines whose removal moves the answer most\n  verdict (prioritize)\n" \
           "    +0.150  context: Goal: race in April\n" in r.stdout
    assert "Note: tired" not in r.stdout.split("why")[1]


def test_k_narrows_the_report_and_the_record_keeps_every_candidate(env):
    r = decide(env, "-y", "Is it fun?", "-k", "1", "-x", "0", stdin="fun\ndull\nflat\n",
               rules=[{"q": "fun", "has": "fun", "d": 0.4}])
    assert r.returncode == 0, r.stderr
    assert [row[-1] for row in scores(r.stdout)] == ["fun"]
    assert len(record(env)["ranking"]) == 3


def test_a_decision_file_runs_its_commands_and_skips_a_criterion_whose_when_fails(env):
    Path(env["DECIDE_DIR"]).mkdir()
    (Path(env["DECIDE_DIR"]) / "lunch.json").write_text(json.dumps({
        "question": "Where to eat?",
        "candidates": "printf '%s\\n' '{\"name\": \"cafe\", \"text\": \"cheap cafe\\nnear\"}' 'diner'",
        "criteria": [
            {"name": "cheap", "want": "yes", "question": "Is it cheap?", "context_cmd": "echo Budget: low"},
            {"name": "never", "want": "yes", "question": "Is it open?", "when": "false"},
        ],
    }))
    r = decide(env, "-d", "lunch", rules=[{"q": "cheap", "has": "cheap", "d": 0.3}])
    assert r.returncode == 0, r.stderr
    assert r.stdout.startswith("Where to eat?\n  cheap  want yes  Is it cheap?\n\n")
    assert [row[-1] for row in scores(r.stdout)] == ["cafe", "diner"]
    rec = record(env, "lunch")
    assert rec["decision"] == "lunch" and rec["question"] == "Where to eat?"
    assert rec["criteria"] == [{"kind": "label", "name": "cheap", "want": "yes",
                                "question": "Is it cheap?", "context": "Budget: low"}]
    assert rec["ranking"][0]["text"] == "cheap cafe\nnear"
    assert "never" not in r.stdout


def test_stdin_candidates_win_over_the_decision_files_command(env):
    Path(env["DECIDE_DIR"]).mkdir()
    (Path(env["DECIDE_DIR"]) / "d.json").write_text(json.dumps({
        "candidates": "echo from-command",
        "criteria": [{"name": "ok", "want": "yes", "question": "Is it ok?"}]}))
    r = decide(env, "-d", "d", stdin='{"name": "piped", "text": "from stdin"}\n')
    assert [row[-1] for row in scores(r.stdout)] == ["piped"]


def test_the_record_holds_criteria_context_every_p_and_marks(env):
    r = decide(env, "-y", "Is it fun?", "-c", "Rule: fun wins", "-j",
               stdin='{"name": "a", "text": "fun one\\nplain"}\n',
               rules=[{"q": "fun", "has": "fun", "d": 0.4}])
    assert r.returncode == 0, r.stderr
    printed = json.loads(r.stdout)
    assert printed == record(env)
    assert printed["criteria"] == [{"kind": "label", "name": "q1", "want": "yes",
                                    "question": "Is it fun?", "context": "Rule: fun wins"}]
    (row,) = printed["ranking"]
    assert (row["name"], row["score"], row["p"], row["text"]) == ("a", 0.9, {"q1": 0.9}, "fun one\nplain")
    assert row["marks"] == {"q1": [{"from": "text", "line": "fun one", "delta": 0.4}]}
    assert f"decide: record in {Path(env['XDG_STATE_HOME'])}/decide/adhoc/" in r.stderr


def test_an_unscored_candidate_is_left_out_and_nothing_scored_exits_1(env):
    r = decide(env, "-y", "Is it ok?", stdin="fine\nUNSCORED thing\n")
    assert r.returncode == 0
    assert "decide: classif could not score UNSCORED thing" in r.stderr
    assert [row[-1] for row in scores(r.stdout)] == ["fine"]
    r = decide(env, "-y", "Is it ok?", stdin="UNSCORED\n")
    assert r.returncode == 1
    assert "nothing could be scored" in r.stderr


def test_no_criteria_is_a_usage_error_and_no_candidates_exits_1(env):
    r = decide(env, stdin="a\n")
    assert r.returncode == 2
    assert "no criteria" in r.stderr
    r = decide(env, "-y", "Is it ok?", stdin="")
    assert r.returncode == 1
    assert "no candidates" in r.stderr


def test_one_line_text_without_context_is_not_marked(env):
    r = decide(env, "-y", "Is it ok?", stdin="only line\n")
    assert "why only line: not marked, the text has 1 line and no context has 1 to 60" in r.stdout
