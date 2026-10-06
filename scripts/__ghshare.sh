#!/usr/bin/env bash
# Share a secret with a colleague by encrypting it to their public key on
# GitHub, or open one shared with you. The direction comes from the input.
#
# Usage: ghshare [login]                 encrypt; hidden prompt for the secret
#        pass show x | ghshare [login]   encrypt the piped secret
#        ghshare                         clipboard holds a block for you: decrypt it
#        ghshare secret.asc              decrypt a saved block
#        xsel -ob | ghshare              decrypt a piped block
#        ghshare -d [file]               force decrypt (file, stdin or clipboard)
# With no login and nothing to decrypt, pick a loft-sh member with fzf.
#
# Decrypt tries every private key you hold: the gpg keyring for PGP, every
# SSH private key in ~/.ssh for age, and every PEM private key for CMS/PKCS7.
# A clipboard block none of them opens, such as the message ghshare just
# copied for someone else, is ignored and ghshare shares instead.
#
# A published GPG key wins over SSH keys when sharing: a GPG key implies the
# recipient already has gpg, while an SSH key says nothing about age.
# Nothing is written to disk in plaintext and the secret never reaches argv.

set -eo pipefail

github_base="${GHSHARE_GITHUB_BASE:-https://github.com}"
ghuser_cmd="${GHSHARE_GHUSER_CMD:-/home/decoder/dev/dotfiles/scripts/__ghuser.sh}"
key_dir="${GHSHARE_KEY_DIR:-$HOME/.ssh}"

die() {
	echo "ghshare: $*" >&2
	exit 1
}

# Print the kind (pgp, age, cms) of the first armored encrypted block in $1,
# then the block itself. Fails when $1 holds none.
find_block() {
	local input="$1" kind begin end block
	for kind in pgp age cms; do
		case "$kind" in
		pgp) begin='-----BEGIN PGP MESSAGE-----' end='-----END PGP MESSAGE-----' ;;
		age) begin='-----BEGIN AGE ENCRYPTED FILE-----' end='-----END AGE ENCRYPTED FILE-----' ;;
		cms) begin='-----BEGIN (PKCS7|CMS)-----' end='-----END (PKCS7|CMS)-----' ;;
		esac
		block=$(printf '%s\n' "$input" | sed -En "/^${begin}\$/,/^${end}\$/p")
		if [[ -n "$block" ]]; then
			printf '%s\n%s\n' "$kind" "$block"
			return 0
		fi
	done
	return 1
}

# Private key files in the key dir whose header matches the extended regex $1.
private_keys() {
	local f
	for f in "$key_dir"/*; do
		[[ -f "$f" && -r "$f" && "$f" != *.pub ]] || continue
		if head -1 "$f" 2>/dev/null | grep -Eq -- "$1"; then printf '%s\n' "$f"; fi
	done
}

# Decrypt the block in $1 to stdout with any private key the user holds.
# Returns 2 when there is no block, 1 when no key opens it.
decrypt_input() {
	local found kind block ids=() key
	found=$(find_block "$1") || return 2
	kind=${found%%$'\n'*}
	block=${found#*$'\n'}
	case "$kind" in
	pgp)
		printf '%s\n' "$block" | gpg --batch --quiet --decrypt
		;;
	age)
		while IFS= read -r key; do ids+=(-i "$key"); done < <(private_keys '^-----BEGIN (OPENSSH|RSA) PRIVATE KEY-----$')
		((${#ids[@]})) || return 1
		printf '%s\n' "$block" | age --decrypt "${ids[@]}"
		;;
	cms)
		block=$(printf '%s\n' "$block" | sed -E 's/(BEGIN|END) PKCS7/\1 CMS/')
		while IFS= read -r key; do
			if printf '%s\n' "$block" | openssl cms -decrypt -inform PEM -inkey "$key" 2>/dev/null; then
				return 0
			fi
		done < <(private_keys '^-----BEGIN (RSA |EC )?PRIVATE KEY-----$')
		return 1
		;;
	esac
}

# Pick a login from the loft-sh member cache with fzf.
pick_login() {
	"$ghuser_cmd" --list | fzf -d'|' --with-nth=2,1 --prompt='share with> ' | cut -d'|' -f1
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

# Encrypt $2 to $1's GitHub key and print, then copy, a Slack-ready message.
share() {
	local login="$1" secret="$2" gpg_key ssh_keys cipher how message fence='```'
	gpg_key=$(curl -fsS --max-time 15 "$github_base/$login.gpg" 2>/dev/null || true)
	ssh_keys=$(curl -fsS --max-time 15 "$github_base/$login.keys" 2>/dev/null || true)

	if [[ "$gpg_key" == *"BEGIN PGP PUBLIC KEY BLOCK"* ]] &&
		cipher=$(printf '%s' "$secret" | encrypt_gpg "$gpg_key"); then
		how="Save the block as secret.asc and run: gpg -d secret.asc"
	elif cipher=$(printf '%s' "$secret" | encrypt_age "$ssh_keys"); then
		how="Save the block as secret.age and run: age -d -i ~/.ssh/id_ed25519 secret.age (use the private key matching your GitHub SSH key)"
	else
		die "$login publishes no usable GPG or SSH key on GitHub; share it through 1Password instead"
	fi

	message=$(printf 'Encrypted for @%s. %s\n%s\n%s\n%s' "$login" "$how" "$fence" "$cipher" "$fence")
	printf '%s\n' "$message"
	if [[ -z "$GHSHARE_NO_CLIPBOARD" ]] && command -v xsel >/dev/null && [[ -n "$DISPLAY" ]]; then
		printf '%s' "$message" | xsel -ib
		echo "ghshare: copied to clipboard" >&2
	fi
}

main() {
	local arg="$1" piped="" was_piped="" input login secret

	if [[ "$arg" == "-d" || "$arg" == "--decrypt" ]]; then
		if [[ -n "$2" ]]; then
			input=$(cat -- "$2") || die "cannot read $2"
		elif [[ ! -t 0 ]]; then
			input=$(cat)
		else
			input=$(xsel -ob 2>/dev/null) || die "nothing piped and no clipboard to read"
		fi
		decrypt_input "$input" || die "no encrypted block here that your keys can open"
		return
	fi

	# A file argument is a saved block: decrypt it.
	if [[ -n "$arg" && -f "$arg" ]]; then
		decrypt_input "$(cat -- "$arg")" || die "$arg holds no block your keys can open"
		return
	fi

	# Piped input holding a block is a message to open; anything else is a secret.
	if [[ ! -t 0 ]]; then
		was_piped=1
		piped=$(cat)
		if find_block "$piped" >/dev/null; then
			decrypt_input "$piped" || die "the piped block is not for any of your keys"
			return
		fi
	fi

	# Nothing piped and no login: open a clipboard block meant for you. One you
	# cannot open, typically the message just shared, falls through to sharing.
	if [[ -z "$arg" && -t 0 && -z "$GHSHARE_NO_CLIPBOARD" ]] && command -v xsel >/dev/null; then
		input=$(xsel -ob 2>/dev/null || true)
		if find_block "$input" >/dev/null && decrypt_input "$input" 2>/dev/null; then
			return
		fi
	fi

	login="$arg"
	[[ -n "$login" ]] || login=$(pick_login)
	[[ -n "$login" ]] || die "no recipient picked"
	[[ "$login" =~ ^[A-Za-z0-9-]+$ ]] || die "not a GitHub login: $login"

	if [[ -n "$was_piped" ]]; then
		secret="$piped"
	else
		read -rs -p "Secret for $login: " secret </dev/tty
		echo >&2
	fi
	[[ -n "$secret" ]] || die "empty secret"
	share "$login" "$secret"
}

main "$@"
