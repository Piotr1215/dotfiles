#!/usr/bin/env bats
# ghshare encrypts a secret to a colleague's GitHub key. Handing Jan Roehrich a
# Jev API key on 2026-10-06 took a 1Password item, a share link and a delete,
# because 1Password has no send-once message. These tests round-trip real
# throwaway keys: what ghshare prints must decrypt back to the secret.

SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__ghshare.sh"

setup() {
	TMP=$(mktemp -d)
	export GHSHARE_NO_CLIPBOARD=1
	export GHSHARE_GITHUB_BASE="file://$TMP/gh"
	export GHSHARE_KEY_DIR="$TMP/ssh"
	mkdir -p "$TMP/gh" "$TMP/ssh"
}

teardown() {
	gpgconf --homedir "$TMP/gnupg" --kill all 2>/dev/null || true
	rm -rf "$TMP"
}

# Publish a fresh ed25519 SSH key as $TMP/gh/<login>.keys.
publish_ssh() {
	ssh-keygen -q -t ed25519 -N '' -f "$TMP/ssh/id_$1" >/dev/null
	cp "$TMP/ssh/id_$1.pub" "$TMP/gh/$1.keys"
}

# Publish a fresh GPG key with an encryption subkey as $TMP/gh/<login>.gpg.
publish_gpg() {
	mkdir -p -m 700 "$TMP/gnupg"
	gpg --homedir "$TMP/gnupg" --batch --quiet --passphrase '' \
		--quick-gen-key "$1 <$1@example.test>" ed25519 sign 1d
	local fpr
	fpr=$(gpg --homedir "$TMP/gnupg" --with-colons --list-keys "$1" | awk -F: '$1=="fpr"{print $10; exit}')
	gpg --homedir "$TMP/gnupg" --batch --quiet --passphrase '' --quick-add-key "$fpr" cv25519 encr 1d
	gpg --homedir "$TMP/gnupg" --armor --export "$1" >"$TMP/gh/$1.gpg"
}

# Pull the fenced ciphertext out of the Slack message.
ciphertext() {
	printf '%s\n' "$1" | awk '/^```$/{f=!f; next} f'
}

@test "an SSH-only recipient gets an age block that their key decrypts" {
	publish_ssh alice
	run bash -c "printf 's3cret-key' | '$SCRIPT' alice"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Encrypted for @alice"* ]]
	[[ "$output" == *"age -d"* ]]
	ciphertext "$output" | age -d -i "$TMP/ssh/id_alice" >"$TMP/out"
	[ "$(cat "$TMP/out")" = "s3cret-key" ]
}

@test "a GPG recipient gets a PGP block even when SSH keys exist too" {
	publish_ssh bob
	publish_gpg bob
	run bash -c "printf 's3cret-key' | '$SCRIPT' bob"
	[ "$status" -eq 0 ]
	[[ "$output" == *"gpg -d"* ]]
	[[ "$output" == *"BEGIN PGP MESSAGE"* ]]
	ciphertext "$output" | gpg --homedir "$TMP/gnupg" --batch --quiet -d >"$TMP/out"
	[ "$(cat "$TMP/out")" = "s3cret-key" ]
}

@test "the recipient's GPG key never lands in the user's keyring" {
	publish_gpg carol
	export GNUPGHOME="$TMP/userhome"
	mkdir -p -m 700 "$GNUPGHOME"
	run bash -c "printf 's3cret-key' | '$SCRIPT' carol"
	[ "$status" -eq 0 ]
	run gpg --batch --list-keys carol
	[ "$status" -ne 0 ]
}

@test "a recipient with no usable key fails and points at 1Password" {
	printf 'ecdsa-sha2-nistp256 AAAA dave\n' >"$TMP/gh/dave.keys"
	run bash -c "printf 's3cret-key' | '$SCRIPT' dave"
	[ "$status" -eq 1 ]
	[[ "$output" == *"no usable GPG or SSH key"* ]]
	[[ "$output" == *"1Password"* ]]
	[[ "$output" != *"s3cret-key"* ]]
}

@test "an empty secret is refused" {
	publish_ssh erin
	run bash -c "printf '' | '$SCRIPT' erin"
	[ "$status" -eq 1 ]
	[[ "$output" == *"empty secret"* ]]
}

@test "a login that is not a GitHub handle is refused before any fetch" {
	run bash -c "printf 'x' | '$SCRIPT' '../etc/passwd'"
	[ "$status" -eq 1 ]
	[[ "$output" == *"not a GitHub login"* ]]
}

@test "ghshare -d decrypts an age block with the matching SSH identity" {
	publish_ssh frank
	run bash -c "printf 'round-trip' | '$SCRIPT' frank"
	[ "$status" -eq 0 ]
	run bash -c "printf '%s\\n' \"\$1\" | '$SCRIPT' -d" _ "$output"
	[ "$status" -eq 0 ]
	[ "$output" = "round-trip" ]
}

@test "ghshare -d decrypts a PGP block with the user's keyring" {
	publish_gpg grace
	run bash -c "printf 'round-trip' | '$SCRIPT' grace"
	[ "$status" -eq 0 ]
	export GNUPGHOME="$TMP/gnupg"
	run bash -c "printf '%s\\n' \"\$1\" | '$SCRIPT' -d" _ "$output"
	[ "$status" -eq 0 ]
	[ "$output" = "round-trip" ]
}

@test "ghshare -d without a block says so" {
	run bash -c "printf 'just some text' | '$SCRIPT' -d"
	[ "$status" -eq 1 ]
	[[ "$output" == *"no encrypted block"* ]]
}

@test "ghshare -d reads a saved block from a file, as the asc suffix alias calls it" {
	publish_ssh heidi
	run bash -c "printf 'from-file' | '$SCRIPT' heidi"
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" >"$TMP/secret.age"
	run "$SCRIPT" -d "$TMP/secret.age"
	[ "$status" -eq 0 ]
	[ "$output" = "from-file" ]
}

@test "a piped block is opened without -d, so the GS alias works both ways" {
	publish_ssh ivan
	run bash -c "printf 'auto' | '$SCRIPT' ivan"
	[ "$status" -eq 0 ]
	run bash -c "printf '%s\\n' \"\$1\" | '$SCRIPT'" _ "$output"
	[ "$status" -eq 0 ]
	[ "$output" = "auto" ]
}

@test "a saved block passed as a file argument is opened" {
	publish_gpg judy
	run bash -c "printf 'by-path' | '$SCRIPT' judy"
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" >"$TMP/secret.asc"
	export GNUPGHOME="$TMP/gnupg"
	run "$SCRIPT" "$TMP/secret.asc"
	[ "$status" -eq 0 ]
	[ "$output" = "by-path" ]
}

@test "a CMS block opens with a PEM private key from the key dir" {
	openssl req -x509 -newkey rsa:2048 -nodes -subj /CN=kim -days 1 \
		-keyout "$TMP/ssh/kim.pem" -out "$TMP/kim.crt" 2>/dev/null
	printf 'pki-secret' | openssl cms -encrypt -aes256 -outform PEM "$TMP/kim.crt" >"$TMP/msg.pem"
	run "$SCRIPT" "$TMP/msg.pem"
	[ "$status" -eq 0 ]
	[ "$output" = "pki-secret" ]
}

@test "a piped block meant for someone else fails instead of being re-shared" {
	publish_ssh leo
	run bash -c "printf 'not-yours' | '$SCRIPT' leo"
	[ "$status" -eq 0 ]
	rm "$TMP/ssh/id_leo"
	run bash -c "printf '%s\\n' \"\$1\" | '$SCRIPT'" _ "$output"
	[ "$status" -eq 1 ]
	[[ "$output" == *"not for any of your keys"* ]]
}
