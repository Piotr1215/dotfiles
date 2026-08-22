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

# To STDERR, not STDOUT: api()/newest_qualifying_tag()/check_release()/
# check_issue() return their result by printing it, consumed through
# `x="$(fn)"`. A log line on stdout inside any of them would land IN that
# captured value and corrupt the seen/now comparison in main(). __cron_run.sh
# runs this whole script with `2>&1`, so stderr still reaches its per-job log
# and the dashboard message exactly like stdout would.
log() {
	printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "${*:2}" >&2
}

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
		"https://api.github.com/${path}" 2>/dev/null || {
		log WARN "api call failed, treating as unreachable: ${path}"
		echo 'null'
	}
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
	log INFO "state updated: release_notified=${release:-<none>} issue_notified=${issue:-<none>}"
}

send_mail() {
	local subject="$1" body="$2"
	log INFO "step: sending mail: ${subject}"
	{
		printf 'Subject: %s\n' "$subject"
		printf 'From: %s\n' "$RECIPIENT"
		printf 'To: %s\n\n' "$RECIPIENT"
		printf '%s\n' "$body"
	} | sh -c "$MAILER"
	log INFO "mail sent: ${subject}"
}

# The newest tag past the baseline, across the latest release and the tag list.
# Empty when upstream is still on 3.7.
newest_qualifying_tag() {
	local tag
	tag="$(api "repos/${REPO}/releases/latest" release | jq -r '.tag_name // empty' 2>/dev/null || true)"
	if [ -n "$tag" ] && past_baseline "$tag"; then
		log INFO "release check: latest release ${tag} is past baseline ${BASELINE_MAJOR}.${BASELINE_MINOR}"
		printf '%s\n' "$tag"
		return 0
	fi
	while read -r tag; do
		[ -n "$tag" ] || continue
		if past_baseline "$tag"; then
			log INFO "release check: tag ${tag} is past baseline ${BASELINE_MAJOR}.${BASELINE_MINOR}"
			printf '%s\n' "$tag"
			return 0
		fi
	done < <(api "repos/${REPO}/tags" tags | jq -r '.[]?.name // empty' 2>/dev/null || true)
	log INFO "release check: nothing past baseline ${BASELINE_MAJOR}.${BASELINE_MINOR} yet"
	return 0
}

check_release() {
	local seen="$1" tag
	tag="$(newest_qualifying_tag)"
	[ -n "$tag" ] || return 0
	if [ "$tag" = "$seen" ]; then
		log INFO "release check: ${tag} already notified, no new mail"
		printf '%s\n' "$seen"
		return 0
	fi
	log INFO "release check: ${tag} is new and unnotified"
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
	if [ -z "$state" ]; then
		log WARN "issue check: could not read state for #${ISSUE_NUMBER}"
		return 0
	fi
	if [ "$state" = "open" ]; then
		log INFO "issue check: #${ISSUE_NUMBER} still open"
		return 0
	fi
	if [ "$state" = "$seen" ]; then
		log INFO "issue check: #${ISSUE_NUMBER} already notified as ${state}"
		printf '%s\n' "$seen"
		return 0
	fi
	log INFO "issue check: #${ISSUE_NUMBER} is now ${state} and unnotified"
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
	local release_seen issue_seen

	log INFO "step: reading previous watch state (${STATE_FILE})"
	release_seen="$(read_state release_notified)"
	issue_seen="$(read_state issue_notified)"
	log INFO "previous state: release_notified=${release_seen:-<none>} issue_notified=${issue_seen:-<none>}"

	log INFO "step: checking tmux releases against baseline ${BASELINE_MAJOR}.${BASELINE_MINOR}"
	RELEASE_NOW="$(check_release "$release_seen")"

	log INFO "step: checking issue #${ISSUE_NUMBER} state"
	ISSUE_NOW="$(check_issue "$issue_seen")"

	if [ "$RELEASE_NOW" != "$release_seen" ] || [ "$ISSUE_NOW" != "$issue_seen" ]; then
		HIT=1
		log INFO "step: persisting updated watch state"
		write_state "$RELEASE_NOW" "$ISSUE_NOW"
	else
		log INFO "no change since last check"
	fi
}

HIT=0
RELEASE_NOW=""
ISSUE_NOW=""
START_TS=$(date +%s)

# Runs on every exit path. Unconditional, so a quiet week (the common case)
# still leaves one countful line instead of looking identical to a job that
# never fired. hit=1 is what promotes the exit code to 2 below.
emit_summary() {
	local rc=$?
	local duration
	duration=$(($(date +%s) - START_TS))
	log INFO "SUMMARY: release_notified=${RELEASE_NOW:-<none>} issue_notified=${ISSUE_NOW:-<none>} hit=${HIT} duration_s=${duration}"
	if [ "$rc" -eq 0 ] && [ "$HIT" -eq 1 ]; then
		rc=2
	fi
	exit "$rc"
}
trap emit_summary EXIT

main "$@"
