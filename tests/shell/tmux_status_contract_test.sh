#!/usr/bin/env bash
# Cross-contract test: the status writer and the status inspector, run against
# ONE set of fixtures, must agree.
#
# __tmux_full_status.sh (prefix g) deliberately does not source
# __tmux_active_task.sh. An inspector that shares reads with the writer it
# inspects agrees with that writer's bugs, so the duplication is the point.
#
# The duplication has already cost once. The writer gained a 60-character
# headline cap while the inspector went on deriving status-right-length minus
# 24, so prefix g reported "bar shows 116" against a bar showing 60. Nothing
# caught it, because each suite tested its own script in isolation and both
# were internally consistent.
#
# So this asserts the two agree on the policy they both encode:
#   a. the winning source, across the full PR > Linear > desc > goal chain
#   b. the headline length the writer actually emits, against the cap the
#      inspector reports
#
# Both come from running the scripts, never from reading their source. A test
# that greps a constant out of a file passes while the behaviour it stands for
# is broken.
set -uo pipefail

WRITER="$HOME/dev/dotfiles/scripts/__tmux_active_task.sh"
INSPECTOR="$HOME/dev/dotfiles/scripts/__tmux_full_status.sh"

PASS=0
FAIL=0
T=$(mktemp -d)
BIN="$T/bin"
CACHE="$T/cache"
REPO="$T/repo"
mkdir -p "$BIN" "$CACHE" "$REPO"
trap 'rm -rf "$T"' EXIT

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1)); printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s\n    expected: %s\n    actual:   %s\n" "$label" "$expected" "$actual"
    fi
}

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

# A real repo, not a git stub. get_pr_desc resolves owner/repo out of the
# origin URL before it calls gh, and that parsing is part of what decides
# whether the PR source wins at all.
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" remote add origin git@github.com:acme/widgets.git 2>/dev/null

# --- the shared fixtures -------------------------------------------------
# One stub set, both consumers. The writer and the inspector ask for the same
# facts through slightly different calls, so the stubs answer on the last
# argument rather than on an exact argument list.

cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
last="${!#}"
case "$1" in
  display-message)
    case "$last" in
      '#S')                    printf '%s\n' "${STUB_SESSION:-}" ;;
      '#{@claude_goal}')       printf '%s\n' "${STUB_GOAL:-}" ;;
      '#{pane_current_path}')  printf '%s\n' "${STUB_PANE_PATH:-}" ;;
      '#{pane_id}')            printf '%%1\n' ;;
      *)                       printf '\n' ;;
    esac ;;
  show-options)
    case "$last" in
      status-right-length) printf '%s\n' "${STUB_LIMIT:-140}" ;;
      @agent_desc)         printf '%s\n' "${STUB_DESC:-}" ;;
      *)                   printf '\n' ;;
    esac ;;
  *) : ;;
esac
exit 0
EOF

# Both callers ask gh for a bare title on stdout, so the stub ignores the
# differing flags. An unset title exits non-zero, which is how a real gh
# failure reaches the getters.
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
[ -n "${STUB_PR_TITLE:-}" ] || exit 1
printf '%s\n' "$STUB_PR_TITLE"
EOF

# Real jq parses this on both sides, so the export shape is exercised rather
# than assumed.
cat > "$BIN/task" <<'EOF'
#!/usr/bin/env bash
if [ -n "${STUB_LINEAR_DESC:-}" ]; then
    jq -nc --arg d "$STUB_LINEAR_DESC" '[{description:$d}]'
else
    printf '[]\n'
fi
EOF

chmod +x "$BIN/tmux" "$BIN/gh" "$BIN/task"

# --- driving both scripts ------------------------------------------------

set_case() {
    export STUB_SESSION="$1" STUB_PR_TITLE="$2" STUB_LINEAR_DESC="$3"
    export STUB_DESC="$4" STUB_GOAL="$5"
    export STUB_PANE_PATH="$REPO" STUB_LIMIT=140
    rm -f "$CACHE"/*
}

run_writer() {
    PATH="$BIN:$PATH" TMUX_TASK_CACHE_DIR="$CACHE" TMUX_TASK_LOCK_FILE="$T/lock" \
        bash "$WRITER" --update >/dev/null 2>&1
    cat "$CACHE/${STUB_SESSION//\//-}" 2>/dev/null
}

run_inspector() {
    PATH="$BIN:$PATH" TMUX_TASK_CACHE_DIR="$CACHE" COLUMNS=200 \
        bash "$INSPECTOR" "$STUB_SESSION" '%1' 2>&1
}

# The writer names its source with an emoji, but desc and goal share 🤖, so the
# marker text is what tells them apart. Each fixture gets a distinct one.
writer_source() {
    local line="$1"
    case "$line" in
        *PRTITLE*)    echo "pr" ;;
        *LINEARDESC*) echo "linear" ;;
        *AGENTDESC*)  echo "desc" ;;
        *CLAUDEGOAL*) echo "goal" ;;
        *)            echo "none" ;;
    esac
}

# The inspector names it outright, which is the whole point of the tool.
inspector_source() {
    printf '%s' "$1" | grep -oP '\[x\] \K[a-z]+' | head -1
}

# --- a. the winning source, both scripts, same fixture -------------------
# Each case removes the source above it, so the chain is walked top to bottom
# rather than only its ends being sampled.

echo "== PR wins when every source is available =="
set_case "widgets-pr-2340" "PRTITLE" "LINEARDESC" "AGENTDESC" "CLAUDEGOAL"
w=$(writer_source "$(run_writer)"); i=$(inspector_source "$(run_inspector)")
assert_eq "writer picks pr"        "pr" "$w"
assert_eq "inspector agrees"       "$w" "$i"

echo "== Linear wins when the session carries no PR number =="
set_case "devops-1191-ratelimit" "" "LINEARDESC" "AGENTDESC" "CLAUDEGOAL"
w=$(writer_source "$(run_writer)"); i=$(inspector_source "$(run_inspector)")
assert_eq "writer picks linear"    "linear" "$w"
assert_eq "inspector agrees"       "$w" "$i"

echo "== a retired @agent_desc cannot displace the goal on either side =="
# The spawn label used to sit between Linear and the goal. __spawn_agent.sh
# stopped writing it, because a label fixed at spawn time outranked every later
# recap and froze a worker's bar on the instruction it was given. A set option
# must now be inert in both scripts, which is the half of the removal that a
# deleted row cannot demonstrate on its own.
set_case "spawnworker" "" "" "AGENTDESC" "CLAUDEGOAL"
w=$(writer_source "$(run_writer)"); i=$(inspector_source "$(run_inspector)")
assert_eq "writer ignores it"      "goal" "$w"
assert_eq "inspector agrees"       "$w" "$i"

echo "== the pane goal is the last link =="
set_case "dotfiles" "" "" "" "CLAUDEGOAL"
w=$(writer_source "$(run_writer)"); i=$(inspector_source "$(run_inspector)")
assert_eq "writer picks goal"      "goal" "$w"
assert_eq "inspector agrees"       "$w" "$i"

echo "== an empty chain leaves both reporting nothing =="
set_case "dotfiles" "" "" "" ""
w=$(writer_source "$(run_writer)"); i=$(inspector_source "$(run_inspector)")
assert_eq "writer emits no prefix" "none" "$w"
assert_eq "inspector marks no winner" "" "$i"

# --- b. the writer's headline against the inspector's reported cap -------

echo "== the reported cap is the length the writer actually emits =="
set_case "dotfiles" "" "" "" "$(printf 'g%.0s' {1..280})"
line=$(run_writer)
report=$(run_inspector)

# "🤖 <headline> | Sat 00:00 | home" -> <headline>
headline="${line#* }"
headline="${headline%% | *}"
reported=$(printf '%s' "$report" | grep -oP 'bar shows \K[0-9]+' | head -1)

assert_eq "writer truncated the 280-char goal" "yes" \
    "$([ "${#headline}" -lt 280 ] && echo yes || echo no)"
assert_eq "inspector's cap is the writer's real headline length" \
    "${#headline}" "$reported"

echo "== a goal under the cap is reported as complete by both =="
set_case "dotfiles" "" "" "" "a short goal"
line=$(run_writer)
report=$(run_inspector)
headline="${line#* }"; headline="${headline%% | *}"
assert_eq "writer emits it whole"  "a short goal" "$headline"
assert_eq "inspector claims no cut" "yes" \
    "$(printf '%s' "$report" | grep -q 'shown in full' && echo yes || echo no)"

printf "\n%s passed, %s failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
