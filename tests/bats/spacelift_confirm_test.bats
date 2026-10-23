#!/usr/bin/env bats
#
# Covers __spacelift_confirm_pick.sh (;;spacelift) without a display or network:
# spacectl, rofi, xdotool, tmux and the browser are stubbed and append to one
# ordered log, so a test reads what was listed, typed and opened.

RUN=01M5M4D20GQYEJY10VYFFYNJW4

load helpers/pr_watch_fixture

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	PICKER="$REPO_ROOT/scripts/__spacelift_confirm_pick.sh"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	export SPY="$BATS_TEST_TMPDIR/spy" FIX="$BATS_TEST_TMPDIR/fix"
	mkdir -p "$STUB_BIN" "$SPY" "$FIX"

	for tool in xdotool notify-send xdg-open layout; do
		printf '#!/usr/bin/env bash\necho "%s $*" >> "$SPY/all.log"\n' "$tool" >"$STUB_BIN/$tool"
	done
	# tmux answers the focused client and the pane's pr-watch list file.
	cat >"$STUB_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
echo "tmux $*" >> "$SPY/all.log"
[[ "$1" == "list-clients" ]] && cat "$FIX/clients" 2>/dev/null
[[ "$1" == "show-options" ]] && cat "$FIX/pane_export" 2>/dev/null
[[ "$1" == "capture-pane" ]] && cat "$FIX/screen" 2>/dev/null
[[ "$1" == "display-message" ]] && cat "$FIX/pane_pid" 2>/dev/null
exit 0
EOF
	cat >"$STUB_BIN/spacectl" <<'EOF'
#!/usr/bin/env bash
echo "spacectl $*" >> "$SPY/all.log"
case "$1 $2" in
"stack list") cat "$FIX/stacks.json" ;;
"stack run")
	for ((i = 1; i <= $#; i++)); do [[ "${!i}" == --id ]] && { j=$((i + 1)); id=${!j}; }; done
	cat "$FIX/runs.$id.json" ;;
esac
EOF
	# rofi keeps the menu it was shown and, with -format i, prints the 0-based
	# index of the row containing $FIX/pick; no pick file is Esc.
	cat >"$STUB_BIN/rofi" <<'EOF'
#!/usr/bin/env bash
cat > "$SPY/rofi.in"
echo "rofi $*" >> "$SPY/all.log"
[[ -f "$FIX/pick" ]] || exit 1
n=$(grep -n -m1 -F "$(cat "$FIX/pick")" "$SPY/rofi.in" | cut -d: -f1)
echo $((n - 1))
EOF
	chmod +x "$STUB_BIN"/*
	export PATH="$STUB_BIN:$PATH"
	# Where the pr-watch list sources are looked for, empty until a test fills them.
	export PR_PICK_CLAUDE_DIRS="$BATS_TEST_TMPDIR/claude" PR_PICK_RUNTIME="$BATS_TEST_TMPDIR/run"
	export PR_PICK_PROC="$BATS_TEST_TMPDIR/proc" PR_PICK_CACHE="$BATS_TEST_TMPDIR/cache"
	export SPACELIFT_CONFIRM_NO_DETACH=1 SPACELIFT_CONFIRM_LAYOUT_DELAY=0
	export SPACELIFT_CONFIRM_LAYOUT_SCRIPT="$STUB_BIN/layout" SPACELIFT_CONFIRM_URL="https://loft.app.spacelift.io"
	unset SPACELIFT_CONFIRM_OPEN PR_PICK_WATCH_FILE

	cat >"$FIX/stacks.json" <<'EOF'
[{"id":"flows-main","state":"UNCONFIRMED"},{"id":"flows-staging","state":"FINISHED"},
 {"id":"tailscale-pam","state":"UNCONFIRMED"}]
EOF
	cat >"$FIX/runs.flows-main.json" <<EOF
[{"id":"$RUN","state":"UNCONFIRMED","commit":{"hash":"98d7de6bac3efaacf04b28061666594d558f5326"},
  "delta":{"addCount":0,"changeCount":1,"deleteCount":4},"title":"feat(pam): turn on receipts (#131)"},
 {"id":"01M5J5N4WT4R6GWN1XPX3Y9HTQ","state":"FINISHED","commit":{"hash":"baf6a5f"},"delta":null,"title":"older"}]
EOF
	cat >"$FIX/runs.tailscale-pam.json" <<'EOF'
[{"id":"01M5PAM0000000000000000000","state":"UNCONFIRMED","commit":{"hash":"725f7e202f3a"},"delta":null,"title":"feat: pam services"}]
EOF
}

typed() { grep '^xdotool type' "$SPY/all.log" | sed 's/^xdotool type --clearmodifiers --delay 12 -- //'; }

@test "lists every waiting run, then types the confirm command for the pick and opens the run" {
	echo "flows-main" >"$FIX/pick"
	run "$PICKER" 11
	[ "$status" -eq 0 ]
	grep -qF "flows-main  feat(pam): turn on receipts (#131)  [+0 ~1 -4, 98d7de6]" "$SPY/rofi.in"
	grep -qF "tailscale-pam  feat: pam services  [plan ?, 725f7e2]" "$SPY/rofi.in"
	! grep -q flows-staging "$SPY/rofi.in"
	[ "$(typed)" = "!spacectl stack confirm --id flows-main --run $RUN --tail" ]
	grep -qF "xdotool key --clearmodifiers BackSpace BackSpace BackSpace BackSpace BackSpace BackSpace BackSpace BackSpace BackSpace BackSpace BackSpace" "$SPY/all.log"
	grep -qF "xdg-open https://loft.app.spacelift.io/stack/flows-main/run/$RUN" "$SPY/all.log"
	grep -qF "layout 18" "$SPY/all.log"
}

@test "runs on stacks the focused worker's watched PRs plan or apply on come first, marked watched" {
	printf '%s\n' "300 %7 /home/u/loft/no-repo" >"$FIX/clients"
	echo "$FIX/watched.json" >"$FIX/pane_export"
	cat >"$FIX/watched.json" <<'EOF'
{"scope":"all","prs":[{"url":"https://github.com/loft-sh/tailscale-acls/pull/3","plans":[],
 "applies":[{"stack":"tailscale-pam","url":"https://loft.app.spacelift.io/stack/tailscale-pam/run/01M5PAM0000000000000000000","phase":"confirm"}]}]}
EOF
	echo "tailscale-pam" >"$FIX/pick"
	run "$PICKER" 11
	[ "$status" -eq 0 ]
	grep -qx "tmux show-options -pqv -t %7 @pr_watch_export" "$SPY/all.log"
	[ "$(sed -n 1p "$SPY/rofi.in")" = "tailscale-pam  feat: pam services  [plan ?, 725f7e2, watched]" ]
	[ "$(sed -n 2p "$SPY/rofi.in")" = "flows-main  feat(pam): turn on receipts (#131)  [+0 ~1 -4, 98d7de6]" ]
	[ "$(typed)" = "!spacectl stack confirm --id tailscale-pam --run 01M5PAM0000000000000000000 --tail" ]
}

@test "a running Claude pane without @pr_watch_export ranks the stacks its pr-watch band shows" {
	printf '%s\n' "300 $PAM_PANE /home/u/loft/flows" >"$FIX/clients"
	claude_registry "$PAM_PANE" "$PAM_SID" "$PR_PICK_CLAUDE_DIRS"
	pam_flags_screen >"$FIX/screen"
	echo '[{"id":"tailscale-pam","state":"UNCONFIRMED"},{"id":"flows-main","state":"UNCONFIRMED"},{"id":"loft-rocks","state":"UNCONFIRMED"}]' >"$FIX/stacks.json"
	echo '[{"id":"01M5ROCKS00000000000000000","state":"UNCONFIRMED","commit":{"hash":"1234567abc"},"delta":null,"title":"feat(flows): turn the pam flags on (#924)"}]' >"$FIX/runs.loft-rocks.json"
	echo "loft-rocks" >"$FIX/pick"
	run "$PICKER" 11
	[ "$status" -eq 0 ]
	[ "$(sed -n 1p "$SPY/rofi.in")" = "flows-main  feat(pam): turn on receipts (#131)  [+0 ~1 -4, 98d7de6, watched]" ]
	[ "$(sed -n 2p "$SPY/rofi.in")" = "loft-rocks  feat(flows): turn the pam flags on (#924)  [plan ?, 1234567, watched]" ]
	[ "$(sed -n 3p "$SPY/rofi.in")" = "tailscale-pam  feat: pam services  [plan ?, 725f7e2]" ]
	[ "$(typed)" = "!spacectl stack confirm --id loft-rocks --run 01M5ROCKS00000000000000000 --tail" ]
}

@test "the trigger is erased only after rofi closes" {
	echo "tailscale-pam" >"$FIX/pick"
	run "$PICKER" 11
	[ "$status" -eq 0 ]
	rofi_line=$(grep -n '^rofi' "$SPY/all.log" | cut -d: -f1)
	key_line=$(grep -n '^xdotool key' "$SPY/all.log" | cut -d: -f1)
	[ "$rofi_line" -lt "$key_line" ]
	[ "$(typed)" = "!spacectl stack confirm --id tailscale-pam --run 01M5PAM0000000000000000000 --tail" ]
}

@test "Esc types nothing and opens nothing" {
	run "$PICKER" 11
	[ "$status" -eq 0 ]
	! grep -q '^xdotool' "$SPY/all.log"
	! grep -q '^xdg-open' "$SPY/all.log"
}

@test "no waiting run says so and never opens rofi" {
	echo '[{"id":"flows-main","state":"FINISHED"}]' >"$FIX/stacks.json"
	run "$PICKER" 11
	[ "$status" -eq 0 ]
	grep -qF "notify-send Spacelift confirm No Spacelift runs wait for confirmation" "$SPY/all.log"
	! grep -q '^rofi' "$SPY/all.log"
}

@test "a stack whose recent runs hold no unconfirmed run is skipped" {
	echo '[{"id":"x","state":"FINISHED","commit":{"hash":"abc"},"title":"done"}]' >"$FIX/runs.tailscale-pam.json"
	echo "flows-main" >"$FIX/pick"
	run "$PICKER" 0
	[ "$status" -eq 0 ]
	! grep -q tailscale-pam "$SPY/rofi.in"
	! grep -q '^xdotool key' "$SPY/all.log"
}

@test "an unexpected stack or run id is never typed" {
	echo '[{"id":"bad;id","state":"UNCONFIRMED"},{"id":"flows-main","state":"UNCONFIRMED"}]' >"$FIX/stacks.json"
	echo '[{"id":"01M; rm -rf ~","state":"UNCONFIRMED","commit":{"hash":"abc"},"title":"evil"}]' >"$FIX/runs.flows-main.json"
	run "$PICKER" 11
	[ "$status" -eq 0 ]
	grep -qF "No Spacelift runs wait for confirmation" "$SPY/all.log"
	! grep -q '^xdotool' "$SPY/all.log"
}

@test "SPACELIFT_CONFIRM_OPEN=0 types the command without a browser" {
	echo "flows-main" >"$FIX/pick"
	SPACELIFT_CONFIRM_OPEN=0 run "$PICKER" 11
	[ "$status" -eq 0 ]
	[ -n "$(typed)" ]
	! grep -q '^xdg-open' "$SPY/all.log"
}

@test "a failed stack list notifies instead of failing" {
	printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB_BIN/spacectl"
	run "$PICKER" 11
	[ "$status" -eq 0 ]
	grep -qF "Could not list Spacelift stacks" "$SPY/all.log"
}
