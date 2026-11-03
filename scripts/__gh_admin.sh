#!/usr/bin/env bash
# PROJECT: secret-picker
# Run gh, or a script that calls gh, with the org-admin token from the bastion.
#
# The daily gh login carries no admin:org scope, so a stolen copy of it cannot
# manage the org. The few calls that need org admin (team membership writes,
# org invitations, SAML identities, team access with --apply) go through here.
# Each run costs a YubiKey tap to decrypt GH_ADMIN_TOKEN, and the token lives
# only in the environment of the command started here.
#
#   __gh_admin.sh api orgs/loft-sh/invitations
#   __gh_admin.sh -- __ghuser.sh
set -eo pipefail

script_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
SECRET_LIB="${SECRET_LIB:-$script_dir/__lib_secret_object.sh}"
GH_BIN="${GH_BIN:-gh}"
ADMIN_SECRET="${GH_ADMIN_SECRET:-GH_ADMIN_TOKEN}"

# Print the usage line to stderr.
usage() {
	printf 'usage: %s <gh arguments>\n       %s -- <command that calls gh>\n' "${0##*/}" "${0##*/}" >&2
}

# Read the admin token, then exec gh (or the command after --) with it.
main() {
	local mode=gh token
	[[ $# -gt 0 ]] || {
		usage
		exit 2
	}
	if [[ "$1" == "--" ]]; then
		mode=cmd
		shift
		[[ $# -gt 0 ]] || {
			usage
			exit 2
		}
	fi
	token=$("$SECRET_LIB" read "$ADMIN_SECRET" 2>/dev/null) || token=""
	[[ -n "$token" ]] || {
		printf '%s: could not read %s from the bastion (no YubiKey tap, or not stored yet: secadd %s)\n' \
			"${0##*/}" "$ADMIN_SECRET" "$ADMIN_SECRET" >&2
		exit 1
	}
	export GH_TOKEN="$token"
	unset token
	[[ "$mode" == cmd ]] && exec "$@"
	exec "$GH_BIN" "$@"
}

main "$@"
