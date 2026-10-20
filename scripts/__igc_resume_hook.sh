#!/usr/bin/env bash
set -eo pipefail

# systemd-sleep hook: reload the Intel igc driver after resume. On serval the
# wired port (enp130s0) wedges on resume, the kernel logs "Timeout reading
# IGC_PTM_STAT register", and NetworkManager fails every activation with
# config-failed until the driver reloads (seen 2026-10-20). A fresh driver
# brings the port back and NetworkManager autoconnects the cable.
#
# Install as root, copied rather than symlinked, since root runs the hook and
# it must not stay user-writable:
#   sudo scripts/__igc_resume_hook.sh install

HOOK_PATH="${IGC_HOOK_PATH:-/etc/systemd/system-sleep/igc-resume}"
MODULE_DIR="${IGC_MODULE_DIR:-/sys/module/igc}"

# Reload igc if it is loaded; a machine without it has nothing to fix. Not
# lsmod | grep -q: under pipefail grep's early exit SIGPIPEs lsmod and the
# check reads as "not loaded".
reload_igc() {
	[ -d "$MODULE_DIR" ] || return 0
	modprobe -r igc
	modprobe igc
}

case "$1" in
pre) ;;
post) reload_igc ;;
install) install -D -m 0755 "$0" "$HOOK_PATH" ;;
*)
	echo "usage: $(basename "$0") pre|post [sleep-type] | install" >&2
	exit 1
	;;
esac
