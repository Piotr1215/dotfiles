#!/usr/bin/env bats
# Covers the watch that mails when tmux ships past 3.7 or issue #5135 closes.

setup() {
	WATCH="${BATS_TEST_DIRNAME}/../../scripts/__tmux_release_watch.sh"
	TMPDIR_TEST="$(mktemp -d)"
	FIXTURES="${TMPDIR_TEST}/fixtures"
	mkdir -p "$FIXTURES"
	export TMUX_WATCH_FIXTURE="$FIXTURES"
	export TMUX_WATCH_STATE="${TMPDIR_TEST}/state.json"
	export TMUX_WATCH_MAILER="cat > ${TMPDIR_TEST}/mail.txt"
}

teardown() {
	rm -rf "$TMPDIR_TEST"
}

# Write the three API payloads the script reads.
fixture() {
	local release_tag="$1" issue_state="$2" tags="$3"
	echo "{\"tag_name\": \"${release_tag}\"}" >"${FIXTURES}/release.json"
	echo "$tags" >"${FIXTURES}/tags.json"
	echo "{\"state\": \"${issue_state}\", \"title\": \"Floating panes discussion\"}" \
		>"${FIXTURES}/issue.json"
}

mail_sent() {
	[ -f "${TMPDIR_TEST}/mail.txt" ]
}

@test "stays silent while upstream is still on 3.7b and the issue is open" {
	fixture "3.7b" "open" '[{"name":"3.7b"},{"name":"3.7a"}]'
	run "$WATCH"
	[ "$status" -eq 0 ]
	run mail_sent
	[ "$status" -ne 0 ]
}

@test "mails when a release past 3.7 appears" {
	fixture "3.8" "open" '[{"name":"3.8"},{"name":"3.7b"}]'
	run "$WATCH"
	[ "$status" -eq 0 ]
	run mail_sent
	[ "$status" -eq 0 ]
	run command cat "${TMPDIR_TEST}/mail.txt"
	[[ "$output" == *"Subject: tmux 3.8 is released"* ]]
	[[ "$output" == *"codex resume 01a00b43-dcbb-7451-8ca5-3a5e01f5b99a"* ]]
}

@test "finds a 3.8 tag even when the latest release still reads 3.7b" {
	fixture "3.7b" "open" '[{"name":"3.8"},{"name":"3.7b"}]'
	run "$WATCH"
	run command cat "${TMPDIR_TEST}/mail.txt"
	[[ "$output" == *"tmux 3.8 is released"* ]]
}

@test "treats a 3.7c point release as still waiting" {
	fixture "3.7c" "open" '[{"name":"3.7c"},{"name":"3.7b"}]'
	run "$WATCH"
	[ "$status" -eq 0 ]
	run mail_sent
	[ "$status" -ne 0 ]
}

@test "a new major counts as past the baseline" {
	fixture "4.0" "open" '[{"name":"4.0"}]'
	run "$WATCH"
	run mail_sent
	[ "$status" -eq 0 ]
}

@test "mails once per release, not on every run" {
	fixture "3.8" "open" '[{"name":"3.8"}]'
	run "$WATCH"
	rm -f "${TMPDIR_TEST}/mail.txt"
	run "$WATCH"
	[ "$status" -eq 0 ]
	run mail_sent
	[ "$status" -ne 0 ]
}

@test "mails when issue 5135 closes" {
	fixture "3.7b" "closed" '[{"name":"3.7b"}]'
	run "$WATCH"
	[ "$status" -eq 0 ]
	run command cat "${TMPDIR_TEST}/mail.txt"
	[[ "$output" == *"Subject: tmux #5135 is closed"* ]]
	[[ "$output" == *"Floating panes discussion"* ]]
	[[ "$output" == *"codex resume 01a00b43-dcbb-7451-8ca5-3a5e01f5b99a"* ]]
}

@test "mails once per issue close, not on every run" {
	fixture "3.7b" "closed" '[{"name":"3.7b"}]'
	run "$WATCH"
	rm -f "${TMPDIR_TEST}/mail.txt"
	run "$WATCH"
	run mail_sent
	[ "$status" -ne 0 ]
}

@test "an unreachable api fires nothing" {
	rm -f "${FIXTURES}"/*.json
	run "$WATCH"
	[ "$status" -eq 0 ]
	run mail_sent
	[ "$status" -ne 0 ]
}
