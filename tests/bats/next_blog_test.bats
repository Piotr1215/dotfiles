#!/usr/bin/env bats

# __next_blog.sh ranks recently active repos as next blog posts from three
# yes/no answers classif gives per repo. These tests stub classif and check
# which repos become candidates, how the answers rank them, what reaches the
# model as context, and what happens when classif cannot score. git runs for
# real on throwaway repos.

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
  # story: alpha 0.9, others 0.5. told: beta 0.8. liked: alpha 0.9, others 0.2.
  # A repo named broken is unscored.
  stub classif '
text="$(cat)"; q="${@: -1}"; ctx="${*: -2:1}"
echo "Q $q" >>"$LOG"; echo "C $ctx" >>"$LOG"
[[ "$text" == *"Project: broken"* ]] && exit 2
y=0.5
case "$q" in
  *"hold a story"*) [[ "$text" == *"Project: alpha"* ]] && y=0.9 ;;
  *"already tell"*) y=0.1; [[ "$text" == *"Project: beta"* ]] && y=0.8 ;;
  *"readers responded"*) y=0.2; [[ "$text" == *"Project: alpha"* ]] && y=0.9 ;;
esac
n="$(awk -v y="$y" "BEGIN { print 1 - y }")"
printf "{\"label\": \"x\", \"p\": {\"yes\": %s, \"no\": %s, \"unknown\": 0}}\n" "$y" "$n"
awk -v y="$y" "BEGIN { exit (y < 0.5) }"'
  export PATH="$T/bin:$PATH"
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

@test "candidates are my recently active repos, a root that is a repo, never the blog" {
  repo "$T/dev/alpha"
  repo "$T/dev/old" me@example.com 90
  repo "$T/dev/theirs" someone@example.com
  repo "$T/solo"
  git init -q "$T/site" && git -C "$T/site" commit -q --allow-empty -m "post"
  NEXT_BLOG_ROOTS="$T/dev:$T/solo:$T" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *alpha* && "$output" == *solo* ]]
  [[ "$output" != *old* && "$output" != *theirs* && "$output" != *site* ]]
}

@test "repos rank by p(story) times p(not told), best first" {
  repo "$T/dev/alpha"
  repo "$T/dev/beta"
  repo "$T/dev/gamma"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  mapfile -t rows <<<"$output"
  [[ "${rows[0]}" == score*repo ]]
  [[ "${rows[1]}" == 0.810*0.9*0.9*-*alpha ]]
  [[ "${rows[2]}" == 0.450*gamma ]]
  [[ "${rows[3]}" == 0.100*beta ]]
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
  printf 'Kubernetes Tools\t900\nA Quiet Post\t3\n' >"$NEXT_BLOG_FEEDBACK"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  mapfile -t rows <<<"$output"
  [[ "${rows[1]}" == 0.729*alpha ]]
  [[ "${rows[2]}" == 0.090*0.2*gamma ]]
  grep -q '^Q Is this work on the same kind of topic' "$LOG"
  grep -A1 'Medium posts readers responded to most' "$LOG" | grep -q 'Kubernetes Tools'
}

@test "an unscored repo is left out with a note; nothing scored exits 1" {
  repo "$T/dev/alpha"
  repo "$T/dev/broken"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not score broken"* && "$output" == *alpha* ]]
  rm -rf "$T/dev/alpha"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "no recent commits exits 1 and says so" {
  repo "$T/dev/old" me@example.com 90
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no repo has commits in the last 30 days"* ]]
}
