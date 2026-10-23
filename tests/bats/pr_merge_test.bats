#!/usr/bin/env bats
#
# Covers __pr_merge_pick.sh (;;merge) and __pr_merge_watch.sh without a display
# or network: gh, rofi, xdotool, tmux and the browser are stubbed and append to
# one ordered log, so a test reads what was listed, typed, opened and floated.

SHA=0123456789abcdef0123456789abcdef01234567

load helpers/pr_watch_fixture

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
[[ "$1" == "show-options" ]] && cat "$FIX/pane_export" 2>/dev/null
[[ "$1" == "capture-pane" ]] && cat "$FIX/screen" 2>/dev/null
[[ "$1" == "display-message" ]] && cat "$FIX/pane_pid" 2>/dev/null
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
"pr view")
	# A PR a pr-watch list names answers its own view.N file.
	f="$FIX/view.$(printf '%s' "$3" | tr -c 'A-Za-z0-9' _).json"
	if [[ -f "$f" ]]; then cat "$f"; else cat "$FIX/pr_view.json"; fi ;;
"api "*/check-runs*)
	# Each poll reads the next checks.N.json and stays on the last one.
	n=$(($(cat "$FIX/polls" 2>/dev/null || echo 0) + 1))
	echo "$n" >"$FIX/polls"
	f="$FIX/checks.$n.json"
	[[ -f "$f" ]] || f=$(ls "$FIX"/checks.*.json | sort -V | tail -n1)
	cat "$f" ;;
"api "*/status) if [[ -f "$FIX/status.json" ]]; then cat "$FIX/status.json"; else echo '{"statuses":[]}'; fi ;;
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
	# Where the pr-watch list sources are looked for, empty until a test fills them.
	export PR_PICK_CLAUDE_DIRS="$BATS_TEST_TMPDIR/claude" PR_PICK_RUNTIME="$BATS_TEST_TMPDIR/run"
	export PR_PICK_PROC="$BATS_TEST_TMPDIR/proc" PR_PICK_CACHE="$BATS_TEST_TMPDIR/cache"
	export PR_MERGE_DIR="$BATS_TEST_TMPDIR/repo" PR_MERGE_NO_DETACH=1 PR_MERGE_LAYOUT_DELAY=0
	export PR_MERGE_LAYOUT_SCRIPT="$STUB_BIN/layout"
	unset PR_MERGE_REPO PR_MERGE_OPEN TMUX TMUX_PANE PR_PICK_WATCH_FILE

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

# One PR as gh pr view answers it: repo, number, state, title, merge state.
view() {
	printf '{"number":%s,"title":"%s","url":"https://github.com/%s/pull/%s","author":{"login":"Piotr1215"},"isDraft":false,"reviewDecision":"REVIEW_REQUIRED","mergeStateStatus":"%s","state":"%s","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}\n' \
		"$2" "$4" "$1" "$2" "$5" "$3" >"$FIX/view.$(printf '%s' "https://github.com/$1/pull/$2" | tr -c 'A-Za-z0-9' _).json"
}

# A worker's pr-watch list (scope all): open PRs in two repos other than the
# pane's, one merged since, and an entry that is no PR URL.
watched_list() {
	cat >"$FIX/watched.json" <<'EOF'
{"scope":"all","prs":[{"url":"https://github.com/loft-sh/flows/pull/54"},{"url":"https://github.com/loft-sh/vcluster-docs/pull/9"},
 {"url":"https://github.com/loft-sh/flows/pull/50"},{"url":"https://github.com/loft-sh/flows/pull/1;rm"}]}
EOF
	view loft-sh/flows 54 OPEN "fix: retry" BLOCKED
	view loft-sh/vcluster-docs 9 OPEN "docs: page" CLEAN
	view loft-sh/flows 50 MERGED "feat: gone" CLEAN
}

@test "no GitHub repo in the focused pane opens no menu and leaves the trigger" {
	rm "$FIX/name"
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	grep -q '^notify-send PR merge No GitHub repo' "$SPY/all.log"
	! grep -q '^rofi\|^xdotool' "$SPY/all.log"
}

@test "the repo is resolved in the pane of the most recently used tmux client" {
	unset PR_MERGE_DIR
	printf '%s\n' "100 %1 /elsewhere" "300 %7 $BATS_TEST_TMPDIR/repo" "200 %3 /older" >"$FIX/clients"
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	grep -q "^tmux list-clients -F #{client_activity} #{pane_id} #{pane_current_path}" "$SPY/all.log"
	grep -qx "tmux show-options -pqv -t %7 @pr_watch_export" "$SPY/all.log"
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

@test "a worker pane's pr-watch list is the menu: its open PRs from every repo, not the pane's repo" {
	watched_list
	PR_PICK_WATCH_FILE="$FIX/watched.json" run "$PICKER" 7
	[ "$status" -eq 0 ]
	[ "$(cat "$SPY/rofi.in")" = "$(printf '%s\n' \
		'loft-sh/flows#54  fix: retry  [checks ok, review required, bypass]  @Piotr1215' \
		'loft-sh/vcluster-docs#9  docs: page  [checks ok, review required]  @Piotr1215')" ]
	grep -q '^rofi .*merge watched PRs' "$SPY/all.log"
	! grep -q '|pr list' "$SPY/all.log"
	! grep -qF 'pull/1;rm' "$SPY/all.log"
}

@test "a watched PR from another repo merges in its own repo, with that repo's method" {
	watched_list
	echo '{"squashMergeAllowed":false,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}' >"$FIX/repo.json"
	echo "loft-sh/vcluster-docs#9 " >"$FIX/pick"
	PR_PICK_WATCH_FILE="$FIX/watched.json" run "$PICKER" 7
	[ "$status" -eq 0 ]
	grep -q '|repo view loft-sh/vcluster-docs --json squashMergeAllowed' "$SPY/all.log"
	[ "$(typed)" = "!gh pr merge 9 --repo loft-sh/vcluster-docs --merge && __pr_merge_watch.sh loft-sh/vcluster-docs 9" ]
	grep -qx 'xdg-open https://github.com/loft-sh/vcluster-docs/pull/9' "$SPY/all.log"
}

@test "the list is the one the focused pane names in @pr_watch_export" {
	unset PR_MERGE_DIR
	watched_list
	printf '%s\n' "300 %7 $BATS_TEST_TMPDIR/repo" >"$FIX/clients"
	echo "$FIX/watched.json" >"$FIX/pane_export"
	echo "loft-sh/flows#54 " >"$FIX/pick"
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	[ "$(typed)" = "!gh pr merge 54 --repo loft-sh/flows --squash --admin && __pr_merge_watch.sh loft-sh/flows 54" ]
}

@test "a pr-watch list with no open PR left falls back to the pane's repo" {
	echo '{"scope":"all","prs":[{"url":"https://github.com/loft-sh/flows/pull/50"}]}' >"$FIX/watched.json"
	view loft-sh/flows 50 MERGED "feat: gone" CLEAN
	PR_PICK_WATCH_FILE="$FIX/watched.json" run "$PICKER" 7
	[ "$status" -eq 0 ]
	grep -q '|pr list --repo loft-sh/ai-agents --state open' "$SPY/all.log"
	[ "$(sed -n 1p "$SPY/rofi.in")" = "#156  fix: own  [checks ok, review required, bypass]  @Piotr1215" ]
}

# The flows-pam-flags-on worker: a Claude session started before its pane had
# @pr_watch_export, whose pr-watch watches PRs in three repos.
pam_flags_pane() {
	unset PR_MERGE_DIR
	printf '%s\n' "300 $PAM_PANE $BATS_TEST_TMPDIR/repo" >"$FIX/clients"
	claude_registry "$PAM_PANE" "$PAM_SID" "$PR_PICK_CLAUDE_DIRS"
	pam_flags_screen >"$FIX/screen"
	view loft-sh/eng-infra-config 66 OPEN "feat(alerts): alert on pam publish failures" BLOCKED
	view loft-sh/loft-prod 924 OPEN "feat(flows): turn the pam flags on" BLOCKED
	view loft-sh/flows 134 OPEN "feat(pam): turn the flags on" CLEAN
}

@test "a running Claude pane without @pr_watch_export lists every PR its pr-watch band shows, from every repo" {
	pam_flags_pane
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	grep -qx "tmux capture-pane -p -e -t $PAM_PANE" "$SPY/all.log"
	[ "$(cat "$SPY/rofi.in")" = "$(printf '%s\n' \
		'loft-sh/eng-infra-config#66  feat(alerts): alert on pam publish failures  [checks ok, review required, bypass]  @Piotr1215' \
		'loft-sh/loft-prod#924  feat(flows): turn the pam flags on  [checks ok, review required, bypass]  @Piotr1215' \
		'loft-sh/flows#134  feat(pam): turn the flags on  [checks ok, review required]  @Piotr1215')" ]
	! grep -q '|pr list' "$SPY/all.log"
	! grep -qF 'pull/68' "$SPY/all.log"
	! grep -qF 'pull/135' "$SPY/all.log"
}

@test "a band PR picked from a running Claude pane merges in its own repo" {
	pam_flags_pane
	echo "loft-sh/loft-prod#924 " >"$FIX/pick"
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	[ "$(typed)" = "!gh pr merge 924 --repo loft-sh/loft-prod --squash --admin && __pr_merge_watch.sh loft-sh/loft-prod 924" ]
}

@test "the file pr-watch keeps for the pane's Claude session wins over its band" {
	pam_flags_pane
	mkdir -p "$PR_PICK_RUNTIME/pr-watch/sessions"
	echo '{"scope":"repo","prs":[{"url":"https://github.com/loft-sh/flows/pull/134"}]}' >"$PR_PICK_RUNTIME/pr-watch/sessions/$PAM_SID.json"
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	[ "$(cat "$SPY/rofi.in")" = 'loft-sh/flows#134  feat(pam): turn the flags on  [checks ok, review required]  @Piotr1215' ]
	! grep -q '^tmux capture-pane' "$SPY/all.log"
}

@test "a Claude process that exited no longer stands for the pane" {
	pam_flags_pane
	sed -i 's/"pid":[0-9]*/"pid":999999999/' "$PR_PICK_CLAUDE_DIRS"/sessions/*.json
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	! grep -q '^tmux capture-pane' "$SPY/all.log"
	grep -q '|pr list --repo loft-sh/ai-agents --state open' "$SPY/all.log"
}

@test "a Codex pane lists the PRs the pr-watch adapter keeps for the threads it runs" {
	unset PR_MERGE_DIR
	local home="$BATS_TEST_TMPDIR/codex-work" thread=01a16866-28e2-7000-b7e8-fabb3469b2a9
	printf '%s\n' "300 %68 $BATS_TEST_TMPDIR/repo" >"$FIX/clients"
	echo "$$" >"$FIX/pane_pid"
	mkdir -p "$PR_PICK_PROC/$$/fd" "$home/plugins/data/agent-plugins/dce07efd"
	ln -s "$home/sessions/2026/10/23/rollout-2026-10-23T12-54-48-$thread.jsonl" "$PR_PICK_PROC/$$/fd/7"
	ln -s /dev/null "$PR_PICK_PROC/$$/fd/8"
	cat >"$home/plugins/data/agent-plugins/dce07efd/$thread.json" <<EOF
{"version":1,"sessionId":"$thread","watcher":{"scope":"all","prs":{
 "https://github.com/loft-sh/eng-infra-config/pull/66":{"url":"https://github.com/loft-sh/eng-infra-config/pull/66","plans":[],"applies":[]},
 "https://github.com/loft-sh/flows/pull/134":{"url":"https://github.com/loft-sh/flows/pull/134","plans":[{"stack":"flows-main"}],"applies":[]}}}}
EOF
	view loft-sh/eng-infra-config 66 OPEN "feat(alerts): alert on pam publish failures" BLOCKED
	view loft-sh/flows 134 OPEN "feat(pam): turn the flags on" CLEAN
	run "$PICKER" 7
	[ "$status" -eq 0 ]
	[ "$(cat "$SPY/rofi.in")" = "$(printf '%s\n' \
		'loft-sh/eng-infra-config#66  feat(alerts): alert on pam publish failures  [checks ok, review required, bypass]  @Piotr1215' \
		'loft-sh/flows#134  feat(pam): turn the flags on  [checks ok, review required]  @Piotr1215')" ]
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

check_json() { printf '{"status":"%s","conclusion":"%s","name":"%s","output":{"title":"%s"}}' "$@"; }
checks() { printf '{"check_runs":[%s]}\n' "$(IFS=,; echo "$*")"; }

@test "watch outside tmux prints the checks once" {
	printf '{"mergeCommit":{"oid":"%s"}}\n' "$SHA" >"$FIX/pr_view.json"
	checks "$(check_json completed success test "")" >"$FIX/checks.1.json"
	echo '{"statuses":[{"context":"ci/legacy","state":"pending","description":"waiting"}]}' >"$FIX/status.json"
	run "$WATCH" loft-sh/ai-agents 156
	[ "$status" -eq 0 ]
	[[ "$(sed -n 1p <<<"$output")" =~ ^ok\ +test\ *$ ]]
	[[ "$(sed -n 2p <<<"$output")" =~ ^running\ +ci/legacy\ +waiting$ ]]
	grep -qF "gh $PWD|api repos/loft-sh/ai-agents/commits/$SHA/check-runs?per_page=100" "$SPY/all.log"
	! grep -q '^tmux' "$SPY/all.log"
}

follow() {
	PR_MERGE_WATCH_INTERVAL=0 PR_MERGE_WATCH_LINGER=0 PR_MERGE_WATCH_NO_RUNS="${NO_RUNS:-180}" \
		run "$WATCH" --follow loft-sh/ai-agents 156 "$SHA" </dev/null
}

@test "follow closes once every check has passed on two polls in a row" {
	checks "$(check_json in_progress "" test "")" >"$FIX/checks.1.json"
	checks "$(check_json completed success test "")" "$(check_json completed skipped lint "")" >"$FIX/checks.2.json"
	follow
	[ "$status" -eq 0 ]
	[[ "$output" == *"All checks passed, closing."* ]]
	[ "$(cat "$FIX/polls")" = 3 ]
}

@test "follow waits for a check that starts after the others passed" {
	checks "$(check_json completed success test "")" >"$FIX/checks.1.json"
	checks "$(check_json completed success test "")" "$(check_json queued "" deploy "")" >"$FIX/checks.2.json"
	checks "$(check_json completed success test "")" "$(check_json completed success deploy "")" >"$FIX/checks.3.json"
	follow
	[ "$status" -eq 0 ]
	[ "$(cat "$FIX/polls")" = 4 ]
}

@test "follow keeps a Spacelift run awaiting confirmation open with the ;;spacelift hint" {
	checks "$(check_json completed success spacelift/flows-staging/tracked "0 to add")" \
		"$(check_json in_progress "" spacelift/flows-main/tracked "Changes are awaiting confirmation")" >"$FIX/checks.1.json"
	checks "$(check_json completed success spacelift/flows-staging/tracked "0 to add")" \
		"$(check_json completed success spacelift/flows-main/tracked "0 to add")" >"$FIX/checks.2.json"
	follow
	[ "$status" -eq 0 ]
	[[ "$output" == *"confirm  spacelift/flows-main/tracked"*"awaiting confirmation"* ]]
	[[ "$output" == *"A Spacelift run waits for confirmation: type ;;spacelift."* ]]
	[[ "$output" == *"All checks passed, closing."* ]]
}

@test "follow keeps a failed check on screen instead of closing" {
	checks "$(check_json completed success test "")" "$(check_json completed failure validate "")" >"$FIX/checks.1.json"
	follow
	[ "$status" -eq 1 ]
	[[ "$output" == *"A check failed. q closes."* ]]
	[[ "$output" != *"closing"* ]]
}

@test "follow counts a failed commit status as a failure" {
	checks "$(check_json completed success test "")" >"$FIX/checks.1.json"
	echo '{"statuses":[{"context":"ci/legacy","state":"error","description":"boom"}]}' >"$FIX/status.json"
	follow
	[ "$status" -eq 1 ]
	[[ "$output" == *"A check failed. q closes."* ]]
}

@test "follow gives up when no check starts" {
	checks >"$FIX/checks.1.json"
	NO_RUNS=0 follow
	[ "$status" -eq 0 ]
	[[ "$output" == *"No checks started for 0123456, closing."* ]]
}

@test "follow rejects a malformed sha" {
	run "$WATCH" --follow loft-sh/ai-agents 156 "abc;rm"
	[ "$status" -eq 1 ]
	[ ! -e "$SPY/all.log" ]
}
