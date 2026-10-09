#!/usr/bin/env bats

# __next_blog.sh holds the commands of the next-blog decision
# (.config/decide/next-blog.json) and runs it through __decide.py. These tests
# stub classif and check which repos become candidates, what reaches the model
# as context, how the answers rank the repos, which lines are marked and what
# the record holds. git, jq and __decide.py run for real.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__next_blog.sh"
  T="$BATS_TEST_TMPDIR"
  export LOG="$T/log" GIT_CONFIG_GLOBAL="$T/gitconfig" XDG_STATE_HOME="$T/state"
  export DECIDE_DIR="${BATS_TEST_DIRNAME}/../../.config/decide"
  git config --global user.email me@example.com
  git config --global user.name me
  mkdir -p "$T/bin" "$T/dev" "$T/site/blog" "$T/site/src/data"
  printf -- '---\ntitle: "Paste tmux Scrollback"\n---\n' >"$T/site/blog/2026-09-05-tmux.mdx"
  echo '[{"title":"Zsh Tricks"}]' >"$T/site/src/data/blogs.json"
  export NEXT_BLOG_POSTS="$T/site/blog" NEXT_BLOG_ROOTS="$T/dev:$T/solo" NEXT_BLOG_FEEDBACK="$T/medium.tsv"
  : >"$LOG"
  # story: 0.9 with alpha's commit line, else 0.5. told: beta 0.8, else 0.1.
  # liked: alpha 0.9, others 0.2. A repo named broken is unscored.
  stub classif '
text="$(cat)"; q="${@: -1}"; ctx="$(cat "${*: -2:1}" 2>/dev/null)"
echo "Q $q" >>"$LOG"; echo "C $ctx" >>"$LOG"
[[ "$text" == *"Project: broken"* ]] && exit 2
y=0.5
case "$q" in
  *"hold a story"*) [[ "$text" == *"- feat: work in alpha"* ]] && y=0.9 ;;
  *"already tell"*) y=0.1; [[ "$text" == *"Project: beta"* ]] && y=0.8 ;;
  *"readers responded"*) y=0.2; [[ "$text" == *"Project: alpha"* ]] && y=0.9 ;;
esac
n="$(awk -v y="$y" "BEGIN { print 1 - y }")"
printf "{\"label\": \"x\", \"p\": {\"yes\": %s, \"no\": %s, \"unknown\": 0}}\n" "$y" "$n"
awk -v y="$y" "BEGIN { exit (y < 0.5) }"'
  export PATH="$T/bin:${BATS_TEST_DIRNAME}/../../scripts:$PATH"
}

stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$T/bin/$1"
  chmod +x "$T/bin/$1"
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
  run "$SCRIPT" -x 0
  [ "$status" -eq 0 ]
  [[ "$output" == "Which recently active repo should the next CloudRumble post be about?"* ]]
  mapfile -t r < <(rows)
  [[ "${r[0]}" == 0.810*0.900*0.900*alpha ]]
  [[ "${r[1]}" == 0.450*gamma ]]
  [[ "${r[2]}" == 0.100*beta ]]
}

@test "published titles from the blog and the site's Medium list reach the told question" {
  repo "$T/dev/alpha"
  run "$SCRIPT" -x 0
  grep -q 'Paste tmux Scrollback' "$LOG"
  grep -q 'Zsh Tricks' "$LOG"
}

@test "a feedback file adds liked from its top posts and counts its titles as published" {
  repo "$T/dev/alpha"
  repo "$T/dev/gamma"
  run "$SCRIPT" -x 0
  [[ "$output" != *liked* ]]
  printf 'Kubernetes Tools\t900\nA Quiet Post\t3\n' >"$NEXT_BLOG_FEEDBACK"
  run "$SCRIPT" -x 0
  [ "$status" -eq 0 ]
  mapfile -t r < <(rows)
  [[ "${r[0]}" == 0.729*alpha ]]
  [[ "${r[1]}" == 0.090*"no 0.800"*gamma ]]
  grep -A1 'Medium posts readers responded to most' "$LOG" | grep -q 'Kubernetes Tools'
  grep -q 'A Quiet Post' "$LOG"
}

@test "the top repo's marks are the lines whose removal moves each answer" {
  repo "$T/dev/alpha"
  repo "$T/dev/gamma"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'why alpha: lines whose removal moves the answer most\n  story\n    +0.400  - feat: work in alpha\n  new\n    (no single line moves it)'* ]]
  [[ "$output" != *"why gamma"* ]]
}

@test "-k narrows the report, -j prints the record" {
  repo "$T/dev/alpha"
  repo "$T/dev/gamma"
  run "$SCRIPT" -x 0 -k 1
  [ "$(rows | wc -l)" -eq 1 ]
  run "$SCRIPT" -x 0 -j
  [ "$(jq -r '.decision' <<<"${output%%decide: record*}")" = next-blog ]
}

@test "the record holds the criteria with their context, every p, the texts and the marks" {
  repo "$T/dev/alpha"
  repo "$T/dev/beta"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  record="$(ls "$XDG_STATE_HOME"/decide/next-blog/*.json)"
  [[ "$output" == *"decide: record in $record"* ]]
  [ "$(jq -c '.criteria | map([.name, .want])' "$record")" = '[["story","yes"],["new","no"]]' ]
  jq -e '.criteria[1].context | contains("Paste tmux Scrollback")' "$record"
  [ "$(jq -c '.ranking | map([.name, .p.story, .p.new])' "$record")" = '[["alpha",0.9,0.9],["beta",0.5,0.2]]' ]
  [ "$(jq -r '.ranking[0].marks.story[0].line' "$record")" = "- feat: work in alpha" ]
  jq -e '.ranking[1] | has("marks") | not' "$record"
}

@test "an unscored repo is left out with a note; nothing scored exits 1" {
  repo "$T/dev/alpha"
  repo "$T/dev/broken"
  run "$SCRIPT" -x 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"classif could not score broken"* && "$output" == *alpha* ]]
  rm -rf "$T/dev/alpha"
  run "$SCRIPT" -x 0
  [ "$status" -eq 1 ]
}
