#!/usr/bin/env bats

# __next_blog.sh asks every recently active repo its questions through
# classif each and ranks the repos by the product of the p each question
# wants. These tests stub classif each and check which repos become
# candidates, what reaches the model as context, how the answers rank the
# repos and which lines are marked. git and jq run for real.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__next_blog.sh"
  T="$BATS_TEST_TMPDIR"
  export LOG="$T/log" GIT_CONFIG_GLOBAL="$T/gitconfig"
  git config --global user.email me@example.com
  git config --global user.name me
  mkdir -p "$T/bin" "$T/dev" "$T/site/blog" "$T/site/src/data"
  printf -- '---\ntitle: "Paste tmux Scrollback"\n---\n' >"$T/site/blog/2026-09-05-tmux.mdx"
  echo '[{"title":"Zsh Tricks"}]' >"$T/site/src/data/blogs.json"
  export NEXT_BLOG_POSTS="$T/site/blog" NEXT_BLOG_ROOTS="$T/dev:$T/solo" NEXT_BLOG_FEEDBACK="$T/medium.tsv"
  : >"$LOG"
  # classif each: story 0.9 with alpha's commit line, else 0.5. told: beta
  # 0.8, else 0.1. liked: alpha 0.9, others 0.2. A repo named broken is
  # unscored. -w marks each line of the top text whose removal moves p.
  cat >"$T/bin/classif" <<'STUB'
#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
assert args.pop(0) == "each"
ctx = args[args.index("-c") + 1]
q = next(a for i, a in enumerate(args) if not a.startswith("-") and (i == 0 or args[i - 1] != "-c"))
with open(os.environ["LOG"], "a") as f:
    f.write(f"Q {q}\nC {ctx}\n")
def p_yes(text):
    if "hold a story" in q:
        return 0.9 if "- feat: work in alpha" in text else 0.5
    if "already tell" in q:
        return 0.8 if "Project: beta" in text else 0.1
    if "readers responded" in q:
        return 0.9 if "Project: alpha" in text else 0.2
    return 0.5
rows = []
for c in (json.loads(l) for l in sys.stdin if l.strip()):
    if "Project: broken" in c["text"]:
        print(f"classif each: {c['name']}: unscored: stub", file=sys.stderr)
        continue
    y = p_yes(c["text"])
    rows.append({"name": c["name"], "score": y, "label": "yes" if y >= 0.5 else "no",
                 "p": {"yes": y, "no": round(1 - y, 4), "unknown": 0}, "text": c["text"]})
if not rows:
    sys.exit(2)
rows.sort(key=lambda r: -r["score"])
if "-w" in args:
    lines = rows[0]["text"].split("\n")
    rows[0]["marks"] = [{"from": "text", "line": l, "delta": round(rows[0]["score"] - p_yes("\n".join(lines[:i] + lines[i + 1:])), 4)}
                        for i, l in enumerate(lines)]
    rows[0]["marks"] = [m for m in rows[0]["marks"] if m["delta"]]
for r in rows:
    del r["text"]
print(json.dumps({"question": q, "items": rows}))
STUB
  chmod +x "$T/bin/classif"
  export PATH="$T/bin:$PATH"
}

# A repo at $1 with one commit by $2 (default me@example.com), $3 days ago.
repo() {
  local when="@$(($(date +%s) - ${3:-0} * 86400)) +0000"
  git init -q "$1"
  GIT_AUTHOR_EMAIL="${2:-me@example.com}" GIT_COMMITTER_DATE="$when" GIT_AUTHOR_DATE="$when" \
    git -C "$1" commit -q --allow-empty -m "feat: work in $(basename "$1")"
}

# The ranking rows of the report, best first.
rows() {
  grep -E '^[0-9]\.[0-9]{3} ' <<<"$output"
}

@test "candidates are my recently active repos, a root that is a repo, never the blog" {
  repo "$T/dev/alpha"
  repo "$T/dev/old" me@example.com 90
  repo "$T/dev/theirs" someone@example.com
  repo "$T/solo"
  git init -q "$T/site" && git -C "$T/site" commit -q --allow-empty -m "post"
  NEXT_BLOG_ROOTS="$T/dev:$T/solo:$T" run "$SCRIPT" candidates
  [ "$status" -eq 0 ]
  [ "$(jq -sc 'map(.name) | sort | unique' <<<"$output")" = '["alpha","solo"]' ]
  [ "$(jq -sr '.[0].text' <<<"$output")" = $'Project: alpha\nRecent commits:\n- feat: work in alpha' ]
}

@test "DAYS reaches the candidates command" {
  repo "$T/dev/alpha" me@example.com 10
  run "$SCRIPT" 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"no candidates"* ]]
  run "$SCRIPT" 14
  [ "$status" -eq 0 ]
  [[ "$output" == *alpha* ]]
}

@test "repos rank by p(story) times p(not told), best first" {
  repo "$T/dev/alpha"
  repo "$T/dev/beta"
  repo "$T/dev/gamma"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "Which recently active repo should the next CloudRumble post be about?"* ]]
  mapfile -t r < <(rows)
  [ "${r[0]}" = "0.810  yes 0.900  no 0.900   alpha" ]
  [ "${r[1]}" = "0.450  yes 0.500  no 0.900   gamma" ]
  [ "${r[2]}" = "0.100  yes 0.500  yes 0.800  beta" ]
}

@test "published titles from the blog and the site's Medium list reach the told question" {
  repo "$T/dev/alpha"
  run "$SCRIPT"
  grep -q 'Paste tmux Scrollback' "$LOG"
  grep -q 'Zsh Tricks' "$LOG"
}

@test "a feedback file adds liked from its top posts and counts its titles as published" {
  repo "$T/dev/alpha"
  repo "$T/dev/gamma"
  run "$SCRIPT"
  [[ "$output" != *liked* ]]
  printf 'Kubernetes Tools\t900\nA Quiet Post\t3\n' >"$NEXT_BLOG_FEEDBACK"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  mapfile -t r < <(rows)
  [ "${r[0]}" = "0.729  yes 0.900  no 0.900  yes 0.900  alpha" ]
  [ "${r[1]}" = "0.090  yes 0.500  no 0.900  no 0.800   gamma" ]
  grep -A1 'Medium posts readers responded to most' "$LOG" | grep -q 'Kubernetes Tools'
  grep -q 'A Quiet Post' "$LOG"
}

@test "-w marks the lines whose removal moves each of the top repo's answers" {
  repo "$T/dev/alpha"
  repo "$T/dev/gamma"
  run "$SCRIPT"
  [[ "$output" != *why* ]]
  run "$SCRIPT" -w
  [ "$status" -eq 0 ]
  [[ "$output" == *$'why alpha: the lines whose removal moves each answer\'s p most\n  story, yes counts; + raised p(yes)\n    +0.400  - feat: work in alpha\n  new, no counts; + raised p(yes)\n    (no single line moves it)' ]]
}

@test "-k shows the top N" {
  repo "$T/dev/alpha"
  repo "$T/dev/gamma"
  run "$SCRIPT" -k 1
  [ "$(rows | wc -l)" -eq 1 ]
}

@test "an unscored repo is left out with a note; nothing scored fails" {
  repo "$T/dev/alpha"
  repo "$T/dev/broken"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"broken: unscored"* && "$output" == *alpha* ]]
  [ "$(rows | grep -c broken)" -eq 0 ]
  rm -rf "$T/dev/alpha"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
}
