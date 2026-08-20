#!/usr/bin/env bash
# Install the tab-detach extension into every LibreWolf profile and wire its
# native messaging host. LibreWolf runs as a flatpak, so the extension cannot
# load unpacked from this repo: the sandbox does not see it. It ships as an
# unsigned xpi copied into each profile, which LibreWolf accepts because it is
# built with MOZ_REQUIRE_SIGNING empty and the pref below turned off.
#
# The host runs outside the sandbox. Firefox asks xdg-desktop-portal for it
# when widget.use-xdg-desktop-portal.native-messaging is 1 (default 0, even
# under flatpak), and the portal reads the manifest from
# ~/.mozilla/native-messaging-hosts on the host side and spawns the host as its
# own child. That portal is an Ubuntu distro patch (xdg-desktop-portal PR 705),
# not upstream, so this path holds on Ubuntu-based hosts only.
#
# Run with the browser closed. It rewrites profile files the browser owns.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="${SCRIPT_DIR}/../.config/firefox-extensions/tab-detach"
EXT_ID="tab-detach@dotfiles"
SUPERSEDED_ID="tabenhanced@firefox" # tabdetach: moves a tab out, never back
LIBREWOLF_DIR="${LIBREWOLF_DIR:-$HOME/.var/app/io.gitlab.librewolf-community/.librewolf}"
HOSTS_DIR="${HOSTS_DIR:-$HOME/.mozilla/native-messaging-hosts}"

if flatpak ps --columns=application 2>/dev/null | grep -qx io.gitlab.librewolf-community; then
	echo "close LibreWolf first: it owns the profile files this rewrites" >&2
	exit 1
fi

# Firefox reads addon metadata from the zip, so the xpi is the directory zipped
# flat. -j would lose nothing here, but a subdirectory would break that, so
# zip from inside the directory instead.
build_xpi() {
	local out="$1"
	rm -f "$out"
	(cd "$EXT_DIR" && zip -q -r "$out" manifest.json background.js content.js)
}

# Profile paths from profiles.ini, relative to LIBREWOLF_DIR.
profiles() {
	sed -n 's/^Path=//p' "${LIBREWOLF_DIR}/profiles.ini"
}

# Prefs as user.js lines: read on every startup, so they survive upgrades and
# do not depend on where this LibreWolf build looks for librewolf.overrides.cfg.
set_pref() {
	local user_js="$1" line="$2"
	touch "$user_js"
	grep -qxF "$line" "$user_js" || echo "$line" >>"$user_js"
}

main() {
	local xpi profile ext_dir user_js
	xpi=$(mktemp --suffix=.xpi)
	build_xpi "$xpi"

	while IFS= read -r profile; do
		ext_dir="${LIBREWOLF_DIR}/${profile}/extensions"
		user_js="${LIBREWOLF_DIR}/${profile}/user.js"
		mkdir -p "$ext_dir"
		install -m 644 "$xpi" "${ext_dir}/${EXT_ID}.xpi"
		rm -f "${ext_dir}/${SUPERSEDED_ID}.xpi"
		set_pref "$user_js" 'user_pref("xpinstall.signatures.required", false);'
		set_pref "$user_js" 'user_pref("widget.use-xdg-desktop-portal.native-messaging", 1);'
		echo "installed ${EXT_ID} into ${profile}"
	done < <(profiles)
	rm -f "$xpi"

	mkdir -p "$HOSTS_DIR"
	ln -sfn "$(cd "${EXT_DIR}/native-host" && pwd)/com.dotfiles.layouts.json" "${HOSTS_DIR}/com.dotfiles.layouts.json"
	echo "host manifest linked at ${HOSTS_DIR}/com.dotfiles.layouts.json"
	# Firefox installs a sideloaded add-on disabled (extensions.autoDisableScopes)
	# and remembers the user's answer per add-on id, so this is a one-time step.
	echo "first install only: enable Tab Detach Toggle in about:addons, then restart LibreWolf"
}

main "$@"
