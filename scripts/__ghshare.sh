#!/usr/bin/env bash
# Encrypt a secret to a colleague's public key on GitHub and print a
# Slack-ready message carrying the ciphertext.
#
# Usage: ghshare [login]                 hidden prompt for the secret
#        pass show x | ghshare [login]   secret on stdin
# With no login, pick a loft-sh member with fzf (the ghuser cache).
#
# A published GPG key wins over SSH keys: a GPG key implies the recipient
# already has gpg, while an SSH key says nothing about age being installed.
# Nothing is written to disk in plaintext and the secret never reaches argv.

set -eo pipefail

github_base="${GHSHARE_GITHUB_BASE:-https://github.com}"
ghuser_cmd="${GHSHARE_GHUSER_CMD:-/home/decoder/dev/dotfiles/scripts/__ghuser.sh}"

die() {
	echo "ghshare: $*" >&2
	exit 1
}

# Pick a login from the loft-sh member cache with fzf.
pick_login() {
	"$ghuser_cmd" --list | fzf -d'|' --with-nth=2,1 --prompt='share with> ' | cut -d'|' -f1
}

# Read the secret from stdin when piped, else from a hidden prompt on the tty.
read_secret() {
	local secret
	if [[ -t 0 ]]; then
		read -rs -p "Secret for $1: " secret </dev/tty
		echo >&2
	else
		secret=$(cat)
	fi
	[[ -n "$secret" ]] || die "empty secret"
	printf '%s' "$secret"
}

# Encrypt stdin to every usable encryption key in an armored GPG export.
# A throwaway GNUPGHOME keeps the recipient out of the user's keyring.
encrypt_gpg() {
	local pubkey="$1" home fpr fprs recipients=()
	home=$(mktemp -d)
	trap 'rm -rf "$home"' RETURN
	printf '%s\n' "$pubkey" | gpg --homedir "$home" --batch --quiet --import 2>/dev/null ||
		return 1
	# pub lines: field 2 validity (e expired, r revoked), field 12 capabilities
	# (uppercase E means the key as a whole can encrypt).
	mapfile -t fprs < <(gpg --homedir "$home" --batch --with-colons --list-keys 2>/dev/null |
		awk -F: '$1=="pub"{ok=($2!="e" && $2!="r" && $12 ~ /E/); next} $1=="fpr" && ok {print $10; ok=0}')
	((${#fprs[@]})) || return 1
	for fpr in "${fprs[@]}"; do recipients+=(--recipient "$fpr"); done
	gpg --homedir "$home" --batch --quiet --armor --encrypt --trust-model always "${recipients[@]}"
}

# Encrypt stdin to every age-compatible SSH key (ed25519, rsa) in a .keys list.
encrypt_age() {
	local keys="$1" recipients
	recipients=$(printf '%s\n' "$keys" | grep -E '^ssh-(ed25519|rsa) ') || return 1
	age --armor -R <(printf '%s\n' "$recipients")
}

main() {
	local login="$1" secret gpg_key ssh_keys cipher how
	[[ -n "$login" ]] || login=$(pick_login)
	[[ -n "$login" ]] || die "no recipient picked"
	[[ "$login" =~ ^[A-Za-z0-9-]+$ ]] || die "not a GitHub login: $login"

	gpg_key=$(curl -fsS --max-time 15 "$github_base/$login.gpg" 2>/dev/null || true)
	ssh_keys=$(curl -fsS --max-time 15 "$github_base/$login.keys" 2>/dev/null || true)

	secret=$(read_secret "$login")

	if [[ "$gpg_key" == *"BEGIN PGP PUBLIC KEY BLOCK"* ]] &&
		cipher=$(printf '%s' "$secret" | encrypt_gpg "$gpg_key"); then
		how="Save the block as secret.asc and run: gpg -d secret.asc"
	elif cipher=$(printf '%s' "$secret" | encrypt_age "$ssh_keys"); then
		how="Save the block as secret.age and run: age -d -i ~/.ssh/id_ed25519 secret.age (use the private key matching your GitHub SSH key)"
	else
		die "$login publishes no usable GPG or SSH key on GitHub; share it through 1Password instead"
	fi

	local message fence='```'
	message=$(printf 'Encrypted for @%s. %s\n%s\n%s\n%s' "$login" "$how" "$fence" "$cipher" "$fence")
	printf '%s\n' "$message"
	if [[ -z "$GHSHARE_NO_CLIPBOARD" ]] && command -v xsel >/dev/null && [[ -n "$DISPLAY" ]]; then
		printf '%s' "$message" | xsel -ib
		echo "ghshare: copied to clipboard" >&2
	fi
}

main "$@"
