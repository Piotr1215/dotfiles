#!/usr/bin/env bash
set -eo pipefail

# Report a failed run once, including the last known version.
fail() {
	local reason=$1
	printf 'zoom update failed: %s; old=%s new=unknown\n' "$reason" "${before:-unknown}" >&2
	notify-send 'Zoom update failed' "$reason" || true
	exit 1
}

# Check the actual meeting process without matching unrelated command lines.
meeting_active() { pgrep -x cpthost >/dev/null; }

# Read the installed Debian package version.
version() { dpkg-query -W -f='${Version}' zoom; }

before=$(version) || fail 'cannot read installed version'
if meeting_active; then
	printf 'zoom update skipped: meeting active; old=%s new=%s\n' "$before" "$before"
	exit 0
fi
running=false
if pgrep -x zoom >/dev/null; then running=true; fi
sudo -n apt-get update -o Dir::Etc::sourcelist=sources.list.d/zoom.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 >/dev/null || fail 'apt update failed'
if meeting_active; then
	printf 'zoom update skipped: meeting active after update; old=%s new=%s\n' "$before" "$before"
	exit 0
fi
sudo -n apt-get install -y --only-upgrade zoom >/dev/null || fail 'apt install failed'
after=$(version) || fail 'cannot read updated version'
if [[ $before == "$after" ]]; then
	printf 'zoom already up to date; old=%s new=%s\n' "$before" "$after"
else
	printf 'zoom updated; old=%s new=%s\n' "$before" "$after"
	if "$running" && ! meeting_active; then
		nohup zoom >/dev/null 2>&1 </dev/null &
	fi
fi
