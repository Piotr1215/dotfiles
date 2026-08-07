#!/usr/bin/env bash
# __yt_dlp_autoupdate.sh - keep yt-dlp current, because YouTube breaks it often.
#
# YouTube changes its player and signature scheme without notice, and a yt-dlp
# more than a few weeks old starts failing in ways that never name the real
# cause: "Requested format is not available", an empty format list, a 403 on a
# stream url. Every one of those reads as a broken player or a broken config,
# and the search for the cause goes anywhere except the version number.
#
# Run daily by yt-dlp-autoupdate.timer. Safe to run by hand.
#
#   __yt_dlp_autoupdate.sh          # upgrade if a newer release exists
#   __yt_dlp_autoupdate.sh --check  # report only, change nothing
set -eo pipefail

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"; }

# pipx owns this install. Calling the venv binary by its real path rather than
# whatever PATH resolves to matters here: there is also an apt yt-dlp at
# /usr/bin/yt-dlp, years older, and which one a given process finds depends on
# its PATH. Upgrading the wrong one would report success and change nothing
# that mpv or yt-x actually runs.
PIPX_BIN="${HOME}/.local/bin/yt-dlp"

current_version() {
	[[ -x $PIPX_BIN ]] || return 1
	"$PIPX_BIN" --version 2>/dev/null
}

main() {
	local before after

	if ! command -v pipx >/dev/null 2>&1; then
		log "pipx not found: nothing to upgrade"
		return 0
	fi
	if ! before=$(current_version); then
		log "yt-dlp not installed at $PIPX_BIN"
		return 0
	fi

	if [[ ${1:-} == --check ]]; then
		log "installed $before"
		return 0
	fi

	# pipx exits 0 whether it upgraded or found nothing to do, so the version
	# either side is what says which happened.
	pipx upgrade yt-dlp >/dev/null 2>&1 || {
		log "pipx upgrade failed, keeping $before"
		return 1
	}

	after=$(current_version || printf 'unknown')
	if [[ $before == "$after" ]]; then
		log "already current at $before"
	else
		log "upgraded $before -> $after"
	fi
}

main "$@"
