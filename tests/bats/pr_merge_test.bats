#!/usr/bin/env bats
#
# Covers __pr_merge_pick.sh (;;merge) and __pr_merge_watch.sh without a display
# or network: gh, rofi, xdotool, tmux and the browser are stubbed and append to
# one ordered log, so a test reads what was listed, typed, opened and floated.

SHA=0123456789abcdef0123456789abcdef01234567

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	PICKER="$REPO_ROOT/scripts/__pr_merge_pick.sh"
	WATCH="$REPO_ROOT/scripts/__pr_merge_watch.sh"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	export SPY="$BATS_TEST_TMPDIR/spy" FIX="$BATS_TEST_TMPDIR/fix"
	mkdir -p "$STUB_BIN" "$SPY" "$FIX" "$BATS_TEST_TMPDIR/repo"

	for tool in xdotool notify-send xdg-open layout; do
		printf '#!/usr/bin/env bash\necho "%s $*" >> "$SPY/all.log"\n' "$tool" >"$STUB_BIN/$tool"
	done
	cat >"$STUB_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
echo "tmux $*" >> "$SPY/all.log"
[[ "$1" == "list-clients" ]] && cat "$FIX/clients"
exit 0
EOF
	cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $PWD|$*" >> "$SPY/all.log"
case "$1 $2" in
"repo view")
	if [[ "$*" == *nameWithOwner* ]]; then
		[[ -f "$FIX/name" ]] || exit 1
		printf '{"nameWithOwner":"%s"}\n' "$(cat "$FIX/name")"
	elif [[ -f "$FIX/repo.json" ]]; then cat "$FIX/repo.json"
	else echo '{"squashMergeAllowed":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}'
	fi ;;
"pr list") cat "$FIX/prs.json" ;;
"pr view") cat "$FIX/pr_view.json" ;;
"run list")
	if [[ "$*" != *--json* ]]; then echo "RUNS $*"; exit 0; fi
	# Each poll reads the next runs.N.json and stays on the last one.
	n=$(($(cat "$FIX/polls" 2>/dev/null || echo 0) + 1))
	echo "$n" >"$FIX/polls"
	f="$FIX/runs.$n.json"
	[[ -f "$f" ]] || f=$(ls "$FIX"/runs.*.json | sort -V | tail -n1)
	cat "$f" ;;
esac
EOF
	# rofi keeps the menu it was shown and picks the row starting with $FIX/pick;
	# no pick file is Esc.
	cat >"$STUB_BIN/rofi" <<'EOF'
#!/usr/bin/env bash
cat > "$SPY/rofi.in"
echo "rofi $*" >> "$SPY/all.log"
[[ -f "$FIX/pick" ]] || exit 1
grep -m1 -F "$(cat "$FIX/pick")" "$SPY/rofi.in"
EOF
	chmod +x "$STUB_BIN"/*
	export PATH="$STUB_BIN:$PATH"
	export PR_MERGE_DIR="$BATS_TEST_TMPDIR/repo" PR_MERGE_NO_DETACH=1 PR_MERGE_LAYOUT_DELAY=0
	export PR_MERGE_LAYOUT_SCRIPT="$STUB_BIN/layout"
	unset PR_MERGE_REPO PR_MERGE_OPEN TMUX TMUX_PANE

	echo "loft-sh/ai-agents" >"$FIX/name"
	cat >"$FIX/prs.json" <<'EOF'
[
 {"number":156,"title":"fix: own","author":{"login":"Piotr1215"},"isDraft":false,"reviewDecision":"REVIEW_REQUIRED","mergeStateStatus":"BLOCKED",
  "statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","state":"SUCCESS"}]},
 {"number":157,"title":"feat: red","author":{"login":"mate"},"isDraft":false,"reviewDecision":"","mergeStateStatus":"BLOCKED",
  "statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"},{"status":"COMPLETED","conclusion":"FAILURE"}]},
 {"number":158,"title":"chore: wip","author":{"login":"mate"},"isDraft":true,"reviewDecision":"","mergeStateStatus":"BLOCKED",
  "statusCheckRollup":[{"status":"IN_PROGRESS","conclusion":""}]},
 {"number":159,"title":"docs: clean","author":{"login":"mate"},"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN",
  "statusCheckRollup":[]},
 {"number":160,"title":"fix: running","author":{"login":"Piotr1215"},"isDraft":false,"reviewDecision":"REVIEW_REQUIRED","mergeStateStatus":"BLOCKED",
  "statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"},{"status":"IN_PROGRESS","conclusion":""}]}
]
EOF
}

typed() { grep '^xdotool type' "$SPY/all.log" | sed 's/^xdotool type --clearmodifiers --delay 12 -- //'; }

@test "no GitHub repo in the focused pane opens no menu and leaves the trigger" {
	rm "$FIX/name"
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	grep -q '^notify-send PR merge No GitHub repo' "$SPY/all.log"
	! grep -q '^rofi\|^xdotool' "$SPY/all.log"
}

@test "the repo is resolved in the pane of the most recently used tmux client" {
	unset PR_MERGE_DIR
	printf '%s\n' "100 /elsewhere" "300 $BATS_TEST_TMPDIR/repo" "200 /older" >"$FIX/clients"
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	grep -q "^tmux list-clients -F #{client_activity} #{pane_current_path}" "$SPY/all.log"
	grep -qF "gh $BATS_TEST_TMPDIR/repo|repo view --json nameWithOwner" "$SPY/all.log"
	grep -q '|pr list --repo loft-sh/ai-agents --state open' "$SPY/all.log"
}

@test "no open PRs notifies and opens no menu" {
	echo '[]' >"$FIX/prs.json"
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	grep -q '^notify-send PR merge No open PRs in loft-sh/ai-agents' "$SPY/all.log"
	! grep -q '^rofi' "$SPY/all.log"
}

@test "the menu shows each PR's checks, review, and whether it bypasses" {
	run "$PICKER" 7
	[ "$(sed -n 1p "$SPY/rofi.in")" = "#156  fix: own  [checks ok, review required, bypass]  @Piotr1215" ]
	[ "$(sed -n 2p "$SPY/rofi.in")" = "#157  feat: red  [checks fail, no review]  @mate" ]
	[ "$(sed -n 3p "$SPY/rofi.in")" = "#158  chore: wip  [checks pending, no review, draft]  @mate" ]
	[ "$(sed -n 4p "$SPY/rofi.in")" = "#159  docs: clean  [checks none, approved]  @mate" ]
	[ "$(sed -n 5p "$SPY/rofi.in")" = "#160  fix: running  [checks pending, review required, bypass after checks]  @Piotr1215" ]
}

@test "Esc types nothing and opens no browser" {
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	! grep -q '^xdotool key\|^xdotool type\|^xdg-open' "$SPY/all.log"
}

@test "a blocked PR with green checks gets --admin, after the trigger is erased" {
	echo "#156 " >"$FIX/pick"
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	grep -qx 'xdotool key --clearmodifiers BackSpace BackSpace BackSpace BackSpace BackSpace BackSpace BackSpace' "$SPY/all.log"
	[ "$(typed)" = "!gh pr merge 156 --repo loft-sh/ai-agents --squash --admin && __pr_merge_watch.sh loft-sh/ai-agents 156" ]
	[ "$(grep -n '^xdotool key' "$SPY/all.log" | cut -d: -f1)" -lt "$(grep -n '^xdotool type' "$SPY/all.log" | cut -d: -f1)" ]
}

@test "failing checks never get --admin" {
	echo "#157 " >"$FIX/pick"
	run "$PICKER" 7
	[ "$(typed)" = "!gh pr merge 157 --repo loft-sh/ai-agents --squash && __pr_merge_watch.sh loft-sh/ai-agents 157" ]
}

@test "a blocked PR with running checks waits for them, then merges with --admin" {
	echo "#160 " >"$FIX/pick"
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	[ "$(typed)" = "!gh pr checks 160 --repo loft-sh/ai-agents --watch --fail-fast >/dev/null && gh pr merge 160 --repo loft-sh/ai-agents --squash --admin && __pr_merge_watch.sh loft-sh/ai-agents 160" ]
}

@test "a draft never gets --admin" {
	echo "#158 " >"$FIX/pick"
	run "$PICKER" 7
	[[ "$(typed)" != *--admin* ]]
}

@test "a mergeable PR needs no --admin" {
	echo "#159 " >"$FIX/pick"
	run "$PICKER" 7
	[ "$(typed)" = "!gh pr merge 159 --repo loft-sh/ai-agents --squash && __pr_merge_watch.sh loft-sh/ai-agents 159" ]
}

@test "the merge method follows the repo settings" {
	echo '{"squashMergeAllowed":false,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}' >"$FIX/repo.json"
	echo "#159 " >"$FIX/pick"
	run "$PICKER" 7
	[[ "$(typed)" == "!gh pr merge 159 --repo loft-sh/ai-agents --merge && "* ]]
}

@test "the pick opens the PR, then tiles with focus on the terminal, after typing" {
	echo "#156 " >"$FIX/pick"
	run "$PICKER" 7
	grep -qx 'xdg-open https://github.com/loft-sh/ai-agents/pull/156' "$SPY/all.log"
	grep -qx 'layout 18' "$SPY/all.log"
	local typed_at opened_at tiled_at
	typed_at=$(grep -n '^xdotool type' "$SPY/all.log" | cut -d: -f1)
	opened_at=$(grep -n '^xdg-open' "$SPY/all.log" | cut -d: -f1)
	tiled_at=$(grep -n '^layout' "$SPY/all.log" | cut -d: -f1)
	[ "$typed_at" -lt "$opened_at" ]
	[ "$opened_at" -lt "$tiled_at" ]
}

@test "PR_MERGE_OPEN=0 skips the browser" {
	echo "#156 " >"$FIX/pick"
	PR_MERGE_OPEN=0 run "$PICKER" 7
	grep -q '^xdotool type' "$SPY/all.log"
	! grep -q '^xdg-open\|^layout' "$SPY/all.log"
}

@test "watch rejects a malformed repo or PR number" {
	run "$WATCH" "loft-sh/ai-agents;rm" 156
	[ "$status" -eq 1 ]
	run "$WATCH" loft-sh/ai-agents abc
	[ "$status" -eq 1 ]
	[ ! -e "$SPY/all.log" ]
}

@test "watch refuses a PR with no merge commit" {
	echo '{"mergeCommit":null}' >"$FIX/pr_view.json"
	TMUX=/tmp/x run "$WATCH" loft-sh/ai-agents 156
	[ "$status" -eq 1 ]
	[[ "$output" == *"has no merge commit yet"* ]]
	! grep -q '^tmux' "$SPY/all.log"
}

@test "watch floats a viddy pane over the merge commit's runs" {
	printf '{"mergeCommit":{"oid":"%s"}}\n' "$SHA" >"$FIX/pr_view.json"
	TMUX=/tmp/x TMUX_PANE=%9 run "$WATCH" loft-sh/ai-agents 156
	[ "$status" -eq 0 ]
	grep -qxF "tmux new-pane -d -x 90% -y 30% -X 5% -Y 2 -t %9 $WATCH --follow loft-sh/ai-agents 156 $SHA" "$SPY/all.log"
}

@test "watch outside tmux prints the runs once" {
	printf '{"mergeCommit":{"oid":"%s"}}\n' "$SHA" >"$FIX/pr_view.json"
	run "$WATCH" loft-sh/ai-agents 156
	[ "$status" -eq 0 ]
	[ "$output" = "RUNS run list --repo loft-sh/ai-agents --commit $SHA" ]
	! grep -q '^tmux' "$SPY/all.log"
}

run_json() { printf '{"status":"%s","conclusion":"%s","workflowName":"%s","event":"push","databaseId":1,"displayTitle":"t"}' "$@"; }

follow() {
	PR_MERGE_WATCH_INTERVAL=0 PR_MERGE_WATCH_LINGER=0 PR_MERGE_WATCH_NO_RUNS="${NO_RUNS:-180}" \
		run "$WATCH" --follow loft-sh/ai-agents 156 "$SHA" </dev/null
}

@test "follow closes once every run has passed on two polls in a row" {
	echo "[$(run_json in_progress "" test)]" >"$FIX/runs.1.json"
	echo "[$(run_json completed success test),$(run_json completed skipped lint)]" >"$FIX/runs.2.json"
	follow
	[ "$status" -eq 0 ]
	[[ "$output" == *"All runs passed, closing."* ]]
	[ "$(cat "$FIX/polls")" = 3 ]
}

@test "follow waits for a workflow that starts after the others passed" {
	echo "[$(run_json completed success test)]" >"$FIX/runs.1.json"
	echo "[$(run_json completed success test),$(run_json queued "" deploy)]" >"$FIX/runs.2.json"
	echo "[$(run_json completed success test),$(run_json completed success deploy)]" >"$FIX/runs.3.json"
	follow
	[ "$status" -eq 0 ]
	[ "$(cat "$FIX/polls")" = 4 ]
}

@test "follow keeps a failed run on screen instead of closing" {
	echo "[$(run_json completed success test),$(run_json completed failure validate)]" >"$FIX/runs.1.json"
	follow
	[ "$status" -eq 1 ]
	[[ "$output" == *"A run failed. q closes."* ]]
	[[ "$output" != *"closing"* ]]
}

@test "follow gives up when no run starts" {
	echo "[]" >"$FIX/runs.1.json"
	NO_RUNS=0 follow
	[ "$status" -eq 0 ]
	[[ "$output" == *"No runs started for 0123456, closing."* ]]
}

@test "follow rejects a malformed sha" {
	run "$WATCH" --follow loft-sh/ai-agents 156 "abc;rm"
	[ "$status" -eq 1 ]
	[ ! -e "$SPY/all.log" ]
}
