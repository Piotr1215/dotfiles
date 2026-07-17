# _pass_export VARIABLE PASS_ENTRY
# Decrypt one password-store entry directly and export it. A failed entry is
# reported and unset without preventing the rest of the environment from loading.
_pass_export() {
	local name="$1" entry="$2" store value
	store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
	if value="$(command gpg -dq -- "$store/$entry.gpg")" && [ -n "$value" ]; then
		export "$name=$value"
	else
		unset "$name"
		printf 'envrc: failed to load pass entry %s\n' "$entry" >&2
	fi
}
