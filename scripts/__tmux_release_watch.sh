#!/usr/bin/env bash
# Watch upstream tmux for the two events that would unblock the floating-pane
# experiment: a release past 3.7, or issue #5135 leaving the open state.
#
# WHY: on 2026-08-16 a session read tmux master's "3.7b to 3.8" changelog heading
# as a shipped 3.8 and proposed replacing a working binary with an unreleased
# build. 3.7b is current and has no tiled-to-floating round-trip, so the work
# waits on upstream. Checking by hand invites the same misreading, so this reads
# release tags and issue state instead of a changelog heading. It mails once per
# event and stays silent otherwise, which keeps a quiet week free.
set -eo pipefail
IFS=$'\n\t'

REPO="tmux/tmux"
ISSUE_NUMBER=5135
BASELINE_MAJOR=3
BASELINE_MINOR=7
RESUME_CMD="codex resume 01a00b43-dcbb-7451-8ca5-3a5e01f5b99a"

STATE_FILE="${TMUX_WATCH_STATE:-$HOME/.local/state/tmux-release-watch.json}"
FIXTURE_DIR="${TMUX_WATCH_FIXTURE:-}"
RECIPIENT="${TMUX_WATCH_RECIPIENT:-piotrzan@gmail.com}"
MAILER="${TMUX_WATCH_MAILER:-msmtp ${RECIPIENT}}"

# Fetch a GitHub API path, or the matching fixture when running under test.
# A failed fetch yields "null" so one unreachable endpoint cannot fire a mail.
api() {
	local path="$1" name="$2" token
	if [ -n "$FIXTURE_DIR" ]; then
		command cat "${FIXTURE_DIR}/${name}.json" 2>/dev/null || echo 'null'
		return 0
	fi
	local -a auth=()
	if token="$(gh auth token 2>/dev/null)" && [ -n "$token" ]; then
		auth=(-H "Authorization: Bearer ${token}")
	fi
	curl -fsSL --max-time 30 "${auth[@]}" \
		-H "Accept: application/vnd.github+json" \
		"https://api.github.com/${path}" 2>/dev/null || echo 'null'
}

# Answer whether a tmux tag such as "3.8" or "3.7b" is past the baseline. The
# trailing letter is a point release of the same minor, so it is dropped.
past_baseline() {
	local tag="${1#v}" major minor
	major="${tag%%.*}"
	minor="${tag#*.}"
	minor="${minor%%[!0-9]*}"
	if ! [[ "$major" =~ ^[0-9]+$ ]] || ! [[ "$minor" =~ ^[0-9]+$ ]]; then
		return 1
	fi
	if [ "$major" -ne "$BASELINE_MAJOR" ]; then
		[ "$major" -gt "$BASELINE_MAJOR" ]
		return
	fi
	[ "$minor" -gt "$BASELINE_MINOR" ]
}

# Read one key out of the state file, empty when absent or unreadable.
read_state() {
	local key="$1"
	[ -f "$STATE_FILE" ] || return 0
	jq -r --arg k "$key" '.[$k] // ""' "$STATE_FILE" 2>/dev/null || true
}

# Rewrite the state file from both keys, so a corrupt file cannot strand one.
write_state() {
	local release="$1" issue="$2" tmp
	mkdir -p "$(dirname "$STATE_FILE")"
	tmp="$(mktemp)"
	jq -n --arg r "$release" --arg i "$issue" \
		'{release_notified: $r, issue_notified: $i}' >"$tmp"
	mv "$tmp" "$STATE_FILE"
}

send_mail() {
	local subject="$1" body="$2"
	{
		printf 'Subject: %s\n' "$subject"
		printf 'From: %s\n' "$RECIPIENT"
		printf 'To: %s\n\n' "$RECIPIENT"
		printf '%s\n' "$body"
	} | sh -c "$MAILER"
}

# The newest tag past the baseline, across the latest release and the tag list.
# Empty when upstream is still on 3.7.
newest_qualifying_tag() {
	local tag
	tag="$(api "repos/${REPO}/releases/latest" release | jq -r '.tag_name // empty' 2>/dev/null || true)"
	if [ -n "$tag" ] && past_baseline "$tag"; then
		printf '%s\n' "$tag"
		return 0
	fi
	while read -r tag; do
		[ -n "$tag" ] || continue
		if past_baseline "$tag"; then
			printf '%s\n' "$tag"
			return 0
		fi
	done < <(api "repos/${REPO}/tags" tags | jq -r '.[]?.name // empty' 2>/dev/null || true)
	return 0
}

check_release() {
	local seen="$1" tag
	tag="$(newest_qualifying_tag)"
	[ -n "$tag" ] || return 0
	[ "$tag" != "$seen" ] || { printf '%s\n' "$seen"; return 0; }
	send_mail "tmux ${tag} is released" "$(
		cat <<-BODY
			tmux ${tag} is out. 3.7b was the last release when this watch was set.

			  https://github.com/${REPO}/releases/tag/${tag}

			Floating panes were the reason to wait: 3.7b has no tiled-to-floating
			round-trip conversion. Read the changelog before replacing the binary,
			then pick the session back up:

			  ${RESUME_CMD}
		BODY
	)"
	printf '%s\n' "$tag"
}

check_issue() {
	local seen="$1" payload state title
	payload="$(api "repos/${REPO}/issues/${ISSUE_NUMBER}" issue)"
	state="$(printf '%s' "$payload" | jq -r '.state // empty' 2>/dev/null || true)"
	title="$(printf '%s' "$payload" | jq -r '.title // empty' 2>/dev/null || true)"
	[ -n "$state" ] || return 0
	[ "$state" != "open" ] || return 0
	[ "$state" != "$seen" ] || { printf '%s\n' "$seen"; return 0; }
	send_mail "tmux #${ISSUE_NUMBER} is ${state}" "$(
		cat <<-BODY
			${REPO}#${ISSUE_NUMBER} (${title}) is now ${state}.

			  https://github.com/${REPO}/issues/${ISSUE_NUMBER}

			That is the floating-pane thread. Check what actually landed before
			assuming the feature shipped, then pick the session back up:

			  ${RESUME_CMD}
		BODY
	)"
	printf '%s\n' "$state"
}

main() {
	local release_seen issue_seen release_now issue_now
	release_seen="$(read_state release_notified)"
	issue_seen="$(read_state issue_notified)"

	release_now="$(check_release "$release_seen")"
	issue_now="$(check_issue "$issue_seen")"

	if [ "$release_now" != "$release_seen" ] || [ "$issue_now" != "$issue_seen" ]; then
		write_state "$release_now" "$issue_now"
	fi
}

main "$@"
