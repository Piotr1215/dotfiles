# Fixtures for the pickers that read pr-watch lists (__lib_pr_watch_export.sh):
# a Claude pane's screen as `tmux capture-pane -p -e` prints it, the Claude
# session registry, and a Codex pane's open rollout and adapter state.
#
# The screen copies the escape sequences tmux 3.7 captured from the
# flows-pam-flags-on pane on 2026-10-23, with the PRs it watched that day: each
# band row opens with its ref linked to the PR (OSC 8), the parts after it are
# separated by " · ", and each Spacelift run is a link of its own. Titles and
# link ids are the fixture's own.

ESC=$'\033'
# The session the flows-pam-flags-on pane ran, and its pane.
PAM_SID=67c466cf-69b6-4c1d-a88a-43da8013c3b8
PAM_PANE=%51

# A Spacelift run part: stack $1, kind $2 (plan or apply).
band_run() {
	printf '%s[38;5;246m \xc2\xb7 %s[39m%s[38;5;220m%s]8;id=r%s;https://loft.app.spacelift.io/stack/%s/run/01M5MB1ZWB0E5C1F6DQJT1JWQ3%s\\%s %s \xe2\x80\xa6%s[39m%s]8;;%s\\' \
		"$ESC" "$ESC" "$ESC" "$ESC" "$1" "$1" "$ESC" "$1" "$2" "$ESC" "$ESC" "$ESC"
}

# A band row: owner/repo $1, number $2, title $3, then its run parts.
band_row() {
	local repo="$1" n="$2" title="$3"
	shift 3
	printf ' %s[38;5;38m%s]8;id=p%s;https://github.com/%s/pull/%s%s\\%s#%s%s[39m%s]8;;%s\\ \xc2\xb7 %s%s[38;5;220m \xc2\xb7 CI \xe2\x80\xa6%s[39m%s\n' \
		"$ESC" "$ESC" "$n" "$repo" "$n" "$ESC" "${repo#*/}" "$n" "$ESC" "$ESC" "$ESC" "$title" "$ESC" "$ESC" "$*"
}

# The flows-pam-flags-on screen: a pr-watch note naming a PR it no longer
# watches, the band's three rows from three repos, and the status line's own
# PR link, which is no band row.
pam_flags_screen() {
	printf '  %s[38;5;231mPR Watch (automated, not the user): loft-sh/eng-infra-config#68 CI is running.%s[39m\n' "$ESC" "$ESC"
	band_row loft-sh/eng-infra-config 66 "feat(alerts): alert on pam publish failures"
	band_row loft-sh/loft-prod 924 "feat(flows): turn the pam flags on" "$(band_run loft-rocks apply)"
	band_row loft-sh/flows 134 "feat(pam): turn the flags on" "$(band_run flows-staging plan)" "$(band_run flows-main plan)"
	printf '  bypass permissions on \xc2\xb7 %s]8;;https://github.com/loft-sh/flows/pull/135%s\\PR #135%s]8;;%s\\\n' "$ESC" "$ESC" "$ESC" "$ESC"
}

# Registers a live Claude process (this shell) in pane $1 with session $2 under
# config root $3, as Claude Code's sessions/<pid>.json does.
claude_registry() {
	mkdir -p "$3/sessions"
	printf '{"pid":%s,"sessionId":"%s","tmux":"flows-pam-flags-on:@26.%s","kind":"interactive"}\n' "$$" "$2" "$1" >"$3/sessions/$$.json"
}
