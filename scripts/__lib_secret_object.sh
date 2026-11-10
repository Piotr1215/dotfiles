#!/usr/bin/env bash
# PROJECT: secret-picker
# One secret is one object; the stores are properties of it.
#
#   store 1  bastion  ~/.secrets/<NAME>.age               read costs a YubiKey tap
#   store 2  pass     ~/.password-store/<sub>/<NAME>.gpg  no tap, decrypts unattended
#   store 3  envrc    _pass_export <VAR> <sub>/<NAME>     a reference, never a value
#
# Invariant: a value lives in store 1 XOR store 2. Store 3 references a store-2
# entry, so it requires store 2 and holds no value of its own. That invariant is
# why this file is small: there is nothing to cascade on a value change, only one
# owner to write, and a tier change is a move rather than a copy. Everything that
# looks like sync here is really reference bookkeeping in store 3.
#
# Membership is derived on every call, never recorded. A manifest would be a
# second source of truth, and this file exists because the first one drifted:
# FRED_API_KEY and LINEAR_API_KEY currently sit in both stores at once, which is
# what `audit` reports and what promote/demote resolve.
#
# Store 3 discovery is direnv's own allow list. Every file under
# $XDG_DATA_HOME/direnv/allow holds the absolute path of an .envrc direnv will
# load, maintained by direnv itself on every `direnv allow`. It needs no upkeep
# here and it is the only list that matches what actually gets loaded. Editing an
# .envrc invalidates its hash, so every write below re-allows the file; skip that
# and the next `cd` silently stops exporting the secret.
#
# The object name is the leaf: FRED_API_KEY, whether it sits at
# ~/.secrets/FRED_API_KEY.age or at personal/FRED_API_KEY. The exported variable
# in store 3 may differ from the name, so references carry their own var.
#
# Sourced by __secret_picker.sh; also runnable as a CLI so the zsh helpers can
# reach the same code without sourcing bash:  __lib_secret_object.sh audit

SECRETS_DIR="${SECRETS_DIR:-$HOME/.secrets}"
PASS_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
AGE_ID="${AGE_ID:-$HOME/.config/age/yubikey-pass-bastion.txt}"
AGE_RECIPIENTS="${AGE_RECIPIENTS:-$HOME/.config/age/recipients.txt}"
DIRENV_ALLOW_DIR="${DIRENV_ALLOW_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/direnv/allow}"
DESC_FILE="$SECRETS_DIR/.descriptions"
BW_NAMES_FILE="$SECRETS_DIR/.bitwarden"

secret_die() {
	printf 'secret: %s\n' "$1" >&2
	return 1
}

# --- descriptions ------------------------------------------------------------
# The sidecar is keyed by NAME, not by store, so a description survives promote
# and demote without being carried anywhere. Plaintext by necessity: the picker
# has to draw before anything is decrypted (see __secret_picker.sh).

secret_desc_get() {
	[[ -r "$DESC_FILE" ]] || return 0
	awk -F' *\\| *' -v want="$1" '
		/^[[:space:]]*#/ { next }
		NF < 2 { next }
		$1 == want { print $2; exit }
	' "$DESC_FILE"
}

# $2 empty deletes the line. Mirrors __secdesc_write in .config/age/secret.zsh:
# comments survive, the entry is rewritten in place rather than appended twice.
secret_desc_set() {
	local name="$1" text="$2" tmp
	[[ -e "$DESC_FILE" ]] || {
		[[ -n "$text" ]] || return 0
		mkdir -p "$SECRETS_DIR" && chmod 700 "$SECRETS_DIR"
		: >"$DESC_FILE"
	}
	tmp="${DESC_FILE}.$$"
	awk -v want="$name" -v text="$text" '
		/^[[:space:]]*#/ { print; next }
		/^[[:space:]]*$/ { print; next }
		{
			split($0, a, /\|/); nm = a[1]
			gsub(/^[ \t]+|[ \t]+$/, "", nm)
			if (nm == want) { seen = 1; if (text != "") print want " | " text; next }
			print
		}
		END { if (!seen && text != "") print want " | " text }
	' "$DESC_FILE" >"$tmp" && mv -f "$tmp" "$DESC_FILE"
}

# --- store 3 -----------------------------------------------------------------

# Absolute paths of every .envrc direnv is currently allowed to load.
secret_envrc_files() {
	local f p
	[[ -d "$DIRENV_ALLOW_DIR" ]] || return 0
	for f in "$DIRENV_ALLOW_DIR"/*; do
		[[ -f "$f" ]] || continue
		p=$(head -1 "$f")
		[[ -n "$p" && -r "$p" ]] && printf '%s\n' "$p"
	done | sort -u
}

# file<TAB>line<TAB>var<TAB>entry for every _pass_export line, optionally filtered
# to one object. One awk over the whole list, not one per file: this runs on every
# picker open. A commented-out line has "#" as $1 and so never matches.
#
# The line number is part of the identity of a reference, not decoration. The same
# entry can be exported under several names in one file, so nothing addressed by
# (file, entry) alone can name a single reference: an edit keyed that way would
# collapse every export of that entry into one.
secret_refs() {
	local -a files=()
	mapfile -t files < <(secret_envrc_files)
	((${#files[@]})) || return 0
	awk -v want="${1:-}" '
		$1 == "_pass_export" && NF >= 3 {
			leaf = $3; sub(/.*\//, "", leaf)
			if (want == "" || leaf == want) print FILENAME "\t" FNR "\t" $2 "\t" $3
		}
	' "${files[@]}"
}

# direnv keys its allow list on the file's content hash, so any edit revokes it.
secret_direnv_allow() {
	command -v direnv >/dev/null 2>&1 || return 0
	direnv allow "$1" >/dev/null 2>&1 ||
		printf 'secret: direnv allow failed for %s, it will not load until you allow it\n' "$1" >&2
}

# --- the object --------------------------------------------------------------

# NAME<TAB>owner<TAB>entry<TAB>refs<TAB>status for every secret on this machine.
#   owner   age | pass | both | none        (both = the invariant is broken)
#   entry   store-2 path, or "-"
#   refs    number of _pass_export references
#   status  ok | conflict | dangling | multi
# "none" with refs is a dangling _pass_export: direnv fails that line at load
# with "failed to load pass entry", which is otherwise only visible as a cd that
# quietly stops exporting.
secret_index() {
	local name entry leaf file
	local -A age_of=() pass_of=() dupe_of=() refs_of=()
	local -A ref_entry=()

	while IFS= read -r name; do
		[[ -n "$name" ]] && age_of["$name"]=1
	done < <(find "$SECRETS_DIR" -maxdepth 1 -type f -name '*.age' -printf '%f\n' 2>/dev/null |
		sed 's/\.age$//')

	# First entry wins and the leaf is flagged: two subtrees holding the same leaf
	# are two objects under one name, which no operation here can disambiguate.
	while IFS= read -r entry; do
		[[ -n "$entry" ]] || continue
		leaf="${entry##*/}"
		if [[ -n "${pass_of[$leaf]:-}" ]]; then
			dupe_of["$leaf"]=1
		else
			pass_of["$leaf"]="$entry"
		fi
	done < <(find "$PASS_DIR" -type f -name '*.gpg' -not -path '*/.git/*' -printf '%P\n' 2>/dev/null |
		sed 's/\.gpg$//' | sort)

	while IFS=$'\t' read -r file _ _ entry; do
		[[ -n "$entry" ]] || continue
		leaf="${entry##*/}"
		refs_of["$leaf"]=$((${refs_of[$leaf]:-0} + 1))
		ref_entry["$leaf"]="$entry"
	done < <(secret_refs)

	local owner status refs
	printf '%s\n' "${!age_of[@]}" "${!pass_of[@]}" "${!refs_of[@]}" |
		sed '/^$/d' | sort -u |
		while IFS= read -r name; do
			entry="${pass_of[$name]:-}"
			refs="${refs_of[$name]:-0}"
			status=ok
			if [[ -n "${age_of[$name]:-}" && -n "$entry" ]]; then
				owner=both
				status=conflict
			elif [[ -n "${age_of[$name]:-}" ]]; then
				owner=age
			elif [[ -n "$entry" ]]; then
				owner=pass
				[[ -n "${dupe_of[$name]:-}" ]] && status=multi
			else
				owner=none
				entry="${ref_entry[$name]:-}"
			fi
			# A reference with no store-2 entry behind it is broken whichever store
			# the value ended up in, so this outranks the multi flag.
			[[ -z "${pass_of[$name]:-}" && "$refs" -gt 0 ]] && status=dangling
			printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$owner" "${entry:--}" "$refs" "$status"
		done
}

secret_locate() {
	secret_index | awk -F'\t' -v n="$1" '$1 == n'
}

secret_audit() {
	secret_index | awk -F'\t' '$5 != "ok"'
}

# --- the card ----------------------------------------------------------------

# An epoch as a local date, or "unknown" where the filesystem kept none: stat %W
# prints 0, or "-" on older coreutils, when there is no birth time.
secret_date() {
	if [[ "$1" =~ ^[0-9]+$ ]] && (($1 > 0)); then
		date -d "@$1" '+%Y-%m-%d %H:%M'
	else
		printf 'unknown\n'
	fi
}

# The key ids pass encrypts entry $1 to: the nearest .gpg-id walking up from the
# entry's directory, which is the lookup pass itself does.
secret_gpg_id() {
	local dir="$PASS_DIR"
	[[ "$1" == */* ]] && dir="$PASS_DIR/${1%/*}"
	while [[ "$dir" == "$PASS_DIR" || "$dir" == "$PASS_DIR"/* ]]; do
		if [[ -r "$dir/.gpg-id" ]]; then
			sed '/^[[:space:]]*$/d' "$dir/.gpg-id" | paste -sd, - | sed 's/,/, /g'
			return 0
		fi
		[[ "$dir" == "$PASS_DIR" ]] && break
		dir="${dir%/*}"
	done
	printf 'unknown\n'
}

# Stanza types in an age header: piv-p256 is the YubiKey, X25519 a plain key such
# as the offline backup. The header is plaintext up to the "---" line.
secret_age_recipients() {
	LC_ALL=C awk '/^---/ { exit } /^-> / && !seen[$2]++ { print $2 }' "$1" | paste -sd, - | sed 's/,/, /g'
}

# Everything known about one secret except its value, as plain text to paste.
# Nothing here decrypts: names, paths, dates, the sidecar description and age's
# header are already plaintext, so a card never costs a tap. It also works on a
# row whose invariant is broken, since that is when the facts are most wanted.
#
# Neither store is a git repo, so Created is the file's birth time. A rename
# keeps it; a bastion value rewrite resets it, because secret_write_age swaps in
# a new file.
secret_card() {
	local name owner entry refs status file
	IFS=$'\t' read -r name owner entry refs status < <(secret_locate "$1")
	[[ -n "$name" ]] || {
		secret_die "no secret named '$1'"
		return 1
	}

	local store desc
	case "$owner" in
	age) store="bastion, one YubiKey tap to read" ;;
	pass) store="pass, no tap" ;;
	both) store="bastion AND pass (conflict)" ;;
	*) store="none, only .envrc references" ;;
	esac
	desc=$(secret_desc_get "$name")

	printf '%-13s %s\n' "Secret:" "$name" "Store:" "$store" "Status:" "$status"
	[[ -n "$desc" ]] && printf '%-13s %s\n' "Description:" "$desc"
	[[ "$entry" != - ]] && printf '%-13s %s\n' "Pass entry:" "$entry"

	local -a files=()
	[[ "$owner" == age || "$owner" == both ]] && files+=("$SECRETS_DIR/$name.age")
	[[ "$owner" == pass || "$owner" == both ]] && files+=("$PASS_DIR/$entry.gpg")
	for file in "${files[@]}"; do
		printf '%-13s %s\n' "File:" "$file"
		if [[ "$file" == *.age ]]; then
			printf '%-13s age: %s\n' "Encrypted to:" "$(secret_age_recipients "$file")"
		else
			printf '%-13s gpg: %s\n' "Encrypted to:" "$(secret_gpg_id "$entry")"
		fi
		printf '%-13s %s\n' "Created:" "$(secret_date "$(stat -c %W "$file")")" \
			"Modified:" "$(secret_date "$(stat -c %Y "$file")")"
	done

	secret_bw_has "$name" && printf '%-13s %s\n' "Bitwarden:" "login item $name (value as of the last push)"
	printf '%-13s %s\n' ".envrc refs:" "$refs"
	local rfile rline rvar
	while IFS=$'\t' read -r rfile rline rvar _; do
		[[ -n "$rfile" ]] && printf '  %s:%s  %s\n' "$rfile" "$rline" "$rvar"
	done < <(secret_refs "$name")
	return 0
}

# --- writes ------------------------------------------------------------------

# Value on stdin. Encrypt to a temp file and swap: `age -o` truncates its target
# first, so a rotate that fails halfway would otherwise destroy the only copy.
secret_write_age() {
	# Separate declarations on purpose: `local a="$1" b="$a"` expands every word
	# before assigning any of them, so b would take the caller's stale a.
	local name="$1"
	local out="$SECRETS_DIR/$name.age"
	local tmp
	[[ -r "$AGE_RECIPIENTS" ]] || {
		secret_die "no recipients file at $AGE_RECIPIENTS"
		return 1
	}
	mkdir -p "$SECRETS_DIR" && chmod 700 "$SECRETS_DIR"
	tmp="$out.new.$$"
	if age -R "$AGE_RECIPIENTS" -o "$tmp"; then
		chmod 600 "$tmp"
		mv -f "$tmp" "$out"
	else
		rm -f "$tmp"
		return 1
	fi
}

# Value on stdin. -m keeps it a single line without pass prompting on the same
# stdin the value is arriving on (the reason passfromenv uses -m -f too).
secret_write_pass() {
	pass insert -m -f "$1" >/dev/null
}

# Print a secret's value. Costs a tap for a bastion object and nothing for a pass
# one, which is the whole difference between the two tiers.
secret_read() {
	local name owner entry refs status
	IFS=$'\t' read -r name owner entry refs status < <(secret_locate "$1")
	case "$owner" in
	age) age -d -i "$AGE_ID" "$SECRETS_DIR/$name.age" ;;
	# No `head -n1` here. That is the pass CLI convention (password on line 1,
	# metadata below), but this store holds whole values written by passfromenv,
	# so truncating silently returned the first line of a PEM or a JSON blob.
	pass) pass show "$entry" ;;
	both) secret_die "'$1' is in both stores; resolve the conflict first" ;;
	*) secret_die "no secret named '$1'" ;;
	esac
}

# Value on stdin, written to whichever store owns the object. One write, no
# confirmation, no cascade: store 3 holds a reference, so it needs nothing.
secret_set() {
	local name owner entry refs status
	IFS=$'\t' read -r name owner entry refs status < <(secret_locate "$1")
	case "$owner" in
	age) secret_write_age "$name" ;;
	pass) secret_write_pass "$entry" ;;
	both) secret_die "'$1' is in both stores; promote or demote it first" ;;
	*) secret_die "no secret named '$1'" ;;
	esac
}

# Value on stdin. Creation chooses one owner up front, so the XOR invariant is
# true from the first write instead of being repaired after two store-specific
# commands happen to use the same name.
secret_create() {
	local name="$1" owner="$2" sub="${3:-}" clash
	[[ -n "$name" ]] || {
		secret_die "create needs a name"
		return 2
	}
	[[ "$name" != -* && "$name" != *[![:alnum:]_.@-]* ]] || {
		secret_die "'$name' is not a valid secret name"
		return 2
	}
	clash=$(secret_locate "$name")
	[[ -z "$clash" ]] || {
		secret_die "'$name' already exists"
		return 1
	}

	case "$owner" in
	age) secret_write_age "$name" ;;
	pass)
		[[ -n "$sub" && "$sub" != -* && "$sub" != */* && -d "$PASS_DIR/$sub" ]] || {
			secret_die "no pass subtree '$sub' in $PASS_DIR"
			return 2
		}
		secret_write_pass "$sub/$name"
		;;
	*)
		secret_die "unknown store '$owner'"
		return 2
		;;
	esac
}

# --- store 3 wiring ----------------------------------------------------------

# Add a reference. Store 3 requires store 2, and the var defaults to the object
# name, which is what every reference on this machine already uses.
secret_link() {
	local name="$1" file="$2" var="${3:-$1}" owner entry refs status
	IFS=$'\t' read -r name owner entry refs status < <(secret_locate "$name")
	[[ "$owner" == pass ]] || {
		secret_die "only a pass secret can be referenced from an .envrc ('$1' is ${owner:-none})"
		return 1
	}
	[[ -w "$file" ]] || {
		secret_die "cannot write $file"
		return 1
	}
	if awk -v e="$entry" '$1 == "_pass_export" && $3 == e { found = 1 } END { exit !found }' "$file"; then
		return 0 # already referenced there; adding a second line would export it twice
	fi
	printf '_pass_export %s %s\n' "$var" "$entry" >>"$file"
	secret_direnv_allow "$file"
}

secret_unlink() {
	local name="$1" file="$2" tmp
	tmp="$file.secretobj.$$"
	awk -v want="$name" '
		$1 == "_pass_export" && NF >= 3 {
			leaf = $3; sub(/.*\//, "", leaf)
			if (leaf == want) next
		}
		{ print }
	' "$file" >"$tmp" || {
		rm -f "$tmp"
		return 1
	}
	cat "$tmp" >"$file" && rm -f "$tmp" # keep the inode: mv would drop the mode
	secret_direnv_allow "$file"
}

secret_unlink_all() {
	local name="$1" file
	while IFS=$'\t' read -r file _ _ _; do
		[[ -n "$file" ]] && secret_unlink "$name" "$file"
	done < <(secret_refs "$name")
}

# --- renaming and reference vars ---------------------------------------------

# Rewrite every reference to $1 so it points at entry $2, and carry the variable
# name to $3 only where it still matched the old name. A var deliberately
# different from the object name is a choice, not a stale copy, so it stays.
secret_rewrite_refs() {
	local old="$1" newentry="$2" newname="$3" file tmp
	while IFS=$'\t' read -r file _ _ _; do
		[[ -n "$file" ]] || continue
		tmp="$file.secretobj.$$"
		awk -v old="$old" -v ne="$newentry" -v nn="$newname" '
			$1 == "_pass_export" && NF >= 3 {
				leaf = $3; sub(/.*\//, "", leaf)
				if (leaf == old) { print "_pass_export " (($2 == old) ? nn : $2) " " ne; next }
			}
			{ print }
		' "$file" >"$tmp" || {
			rm -f "$tmp"
			return 1
		}
		cat "$tmp" >"$file" && rm -f "$tmp"
		secret_direnv_allow "$file"
	done < <(secret_refs "$old")
}

# The name is the object's identity, so a rename moves three things at once: the
# store, the description sidecar, and every _pass_export line naming the old
# entry. A bare `pass mv` leaves those pointing at a path that no longer exists,
# and direnv reports that only as a cd that quietly stops exporting.
secret_rename() {
	local old="$1" new="$2"
	local name owner entry refs status
	IFS=$'\t' read -r name owner entry refs status < <(secret_locate "$old")
	[[ -n "$new" ]] || {
		secret_die "rename needs a new name"
		return 2
	}
	[[ "$new" != -* && "$new" != *[![:alnum:]_.@-]* ]] || {
		secret_die "'$new' is not a valid secret name"
		return 2
	}
	local clash
	clash=$(secret_locate "$new" | cut -f2)
	[[ -z "$clash" ]] || {
		secret_die "'$new' already exists (owner: $clash)"
		return 1
	}
	local desc
	desc=$(secret_desc_get "$old")
	case "$owner" in
	age)
		mv -n -- "$SECRETS_DIR/$old.age" "$SECRETS_DIR/$new.age" || return 1
		;;
	pass)
		local newentry="$new"
		[[ "$entry" == */* ]] && newentry="${entry%/*}/$new"
		# pass mv moves the ciphertext as-is: no decrypt, no re-encrypt, so a
		# subtree that pins its own .gpg-id keeps the key it was encrypted to.
		pass mv -f "$entry" "$newentry" >/dev/null 2>&1 || {
			secret_die "pass mv failed for '$entry'"
			return 1
		}
		secret_rewrite_refs "$old" "$newentry" "$new"
		;;
	both)
		secret_die "'$old' is in both stores; resolve the conflict first"
		return 1
		;;
	*)
		secret_die "no secret named '$old'"
		return 1
		;;
	esac
	[[ -n "$desc" ]] && {
		secret_desc_set "$old" ""
		secret_desc_set "$new" "$desc"
	}
	return 0
}

# --- tier moves --------------------------------------------------------------

# 2 -> 1. Costs no tap: reading pass is unattended by design, and age encrypts
# with a public key. Raising a secret's clearance is therefore free, while
# demote below has to spend a tap, which is the right way round.
# Store 3 references go with it, since they require store 2.
secret_promote() {
	local name owner entry refs status
	IFS=$'\t' read -r name owner entry refs status < <(secret_locate "$1")
	[[ "$owner" == pass ]] || {
		secret_die "'$1' is not a pass secret (owner: ${owner:-none})"
		return 1
	}
	# Read fully, check, then write. Piping the reader straight into the writer
	# means a reader that fails still produces a write, and the writer cannot tell
	# an empty stream from an empty secret: that is how a missed YubiKey tap on a
	# demote created a 0-byte pass entry and a conflict out of a healthy secret.
	# The plaintext sits in a variable for two statements, the same trade secadd
	# makes, and is unset immediately after.
	local value
	value=$(pass show "$entry" 2>/dev/null) || value=""
	[[ -n "$value" ]] || {
		secret_die "pass show returned nothing for '$entry'; nothing was written"
		return 1
	}
	printf '%s' "$value" | secret_write_age "$name" || {
		unset value
		secret_die "could not write the bastion copy of '$name'; pass entry left alone"
		return 1
	}
	unset value
	secret_unlink_all "$name"
	pass rm -f "$entry" >/dev/null 2>&1 || secret_die "removed nothing from pass for '$name'"
}

# 1 -> 2. Costs a tap, because the value has to be read out of the bastion.
# $2 is the pass subtree (personal, work, ...); each pins its own .gpg-id.
secret_demote() {
	local name owner entry refs status sub="$2"
	IFS=$'\t' read -r name owner entry refs status < <(secret_locate "$1")
	[[ "$owner" == age ]] || {
		secret_die "'$1' is not a bastion secret (owner: ${owner:-none})"
		return 1
	}
	[[ -n "$sub" && -d "$PASS_DIR/$sub" ]] || {
		secret_die "no pass subtree '$sub' in $PASS_DIR"
		return 1
	}
	# Same rule as promote: the tap has to succeed before anything is written.
	local value
	value=$(age -d -i "$AGE_ID" "$SECRETS_DIR/$name.age" 2>/dev/null) || value=""
	[[ -n "$value" ]] || {
		secret_die "no tap registered for '$name'; nothing was written to pass"
		return 1
	}
	printf '%s' "$value" | secret_write_pass "$sub/$name" || {
		unset value
		secret_die "pass insert failed; '$name' left in the bastion"
		return 1
	}
	unset value
	rm -f -- "$SECRETS_DIR/$name.age"
}

# Delete the object. From store 2 the references go too, since they cannot
# outlive the entry. From store 1 or 3 nothing else is touched, which is the
# asymmetry you asked for: unlinking an .envrc must never delete the secret.
secret_rm() {
	local name owner entry refs status
	IFS=$'\t' read -r name owner entry refs status < <(secret_locate "$1")
	case "$owner" in
	age)
		rm -f -- "$SECRETS_DIR/$name.age"
		secret_desc_set "$name" ""
		;;
	pass)
		secret_unlink_all "$name"
		pass rm -f "$entry" >/dev/null 2>&1 || {
			secret_die "pass rm failed for '$entry'"
			return 1
		}
		secret_desc_set "$name" ""
		;;
	both) secret_die "'$1' is in both stores; resolve the conflict first" ;;
	*) secret_die "no secret named '$1'" ;;
	esac
}

# --- export: Bitwarden -------------------------------------------------------
# Bitwarden is an export target, not a fourth store. The XOR invariant above
# stays about stores 1 and 2: a push copies the current value into a Bitwarden
# login item named after the object, so the value survives this machine (the
# 7 Nov wipe took the old encfs vault with it). A later value change here is not
# mirrored; push again to refresh. Deleting the object here leaves the item in
# Bitwarden: delete is local, Bitwarden is where a moved secret goes to stay.
#
# Which names Bitwarden holds is the one membership fact that cannot be derived
# when the picker draws, because reading it needs an unlocked vault. So it is
# cached in the plaintext sidecar $BW_NAMES_FILE, and the cache is rebuilt whole
# from `bw list items` on every push, never edited by hand: it is at most one
# push stale, and an item made or deleted in Bitwarden itself shows up on the
# next push. Names only, like .descriptions; no value is ever written there.
#
# The value arrives on stdin and stays off every argv: jq reads it with
# --rawfile /dev/stdin, then bw encode and bw create/edit read their stdin. The
# session comes from BW_SESSION; unlocking is the caller's job, because the
# picker has no terminal and the CLI user already has `bw unlock`.

# jq prefix for reading `bw list items`: the items of a real list, an error for
# anything else. A locked vault makes bw print a password prompt to stderr and
# exit 0 with nothing on stdout, and a plain `.[]` over nothing succeeds, so
# "locked" read as "no items": a wiped badge cache, or a duplicate item on push.
# `input` fails on empty input; --nointeraction makes bw exit 1 instead.
SECRET_BW_ITEMS='input | if type == "array" then .[] else error("not an item list") end'

# True when the last push saw a Bitwarden login item named exactly NAME.
secret_bw_has() {
	[[ -r "$BW_NAMES_FILE" ]] && grep -qxF -- "$1" "$BW_NAMES_FILE"
}

# Rebuild the cache from the open session, plus $1, the name just pushed: a
# client that has not folded its own create into the list yet must not drop the
# badge for the item it made. pipefail inside the substitution, because a
# locked vault piped into jq reads as an empty vault and would wipe every badge.
# The item list carries every password, so it goes bw -> jq over a pipe only.
secret_bw_names_refresh() {
	local names tmp
	names=$(
		set -o pipefail
		bw list items --nointeraction 2>/dev/null | jq -rn "$SECRET_BW_ITEMS"' | select(.type == 1) | .name' 2>/dev/null
	) || {
		secret_die "bw list failed (vault locked?); the Bitwarden badges were left as they were"
		return 1
	}
	mkdir -p "$SECRETS_DIR" && chmod 700 "$SECRETS_DIR"
	tmp="$BW_NAMES_FILE.$$"
	(
		umask 077
		printf '%s\n' "$names" ${1:+"$1"} | grep -v '^$' | sort -u >"$tmp" || true
	)
	mv -f "$tmp" "$BW_NAMES_FILE"
}

# Id of the one item named exactly NAME, empty when there is none. Bitwarden's
# --search is a substring match, so FOO_KEY would also find FOO_KEY_OLD.
#
# Two steps, not one pipe: piped into jq, a locked vault's empty output reads as
# "no such item" unless the caller set pipefail, and the push would then create
# a duplicate instead of failing.
secret_bw_item_id() {
	local items ids
	items=$(bw list items --search "$1" --nointeraction 2>/dev/null) || {
		secret_die "bw list failed (locked? export BW_SESSION=\$(bw unlock --raw))"
		return 1
	}
	ids=$(jq -rn --arg n "$1" "$SECRET_BW_ITEMS"' | select(.name == $n) | .id' <<<"$items" 2>/dev/null) || {
		unset items
		secret_die "bw list returned something that is not an item list"
		return 1
	}
	unset items
	(($(printf '%s' "$ids" | grep -c .) <= 1)) || {
		secret_die "several Bitwarden items are named '$1'; delete the extras first"
		return 1
	}
	printf '%s' "$ids"
}

# Value on stdin. Creates the login item, or replaces its password and notes
# when exactly one item already has this name. Other fields on an existing item
# (username, URIs, folder) are kept.
secret_bw_push() {
	local name owner entry refs status notes id desc value item
	# Buffered, because an empty stdin is what a failed read upstream looks like
	# (a missed tap, gpg-agent down), and pushing it would blank the password in
	# Bitwarden. The x keeps inner trailing newlines that $(...) would strip;
	# printf is a builtin, so the value still never reaches an argv. One final
	# newline is dropped: an interactive `pass insert` stores one, and in a
	# password field it would be pasted into every login form.
	value=$(
		cat
		printf x
	)
	value=${value%x}
	value=${value%$'\n'}
	IFS=$'\t' read -r name owner entry refs status < <(secret_locate "$1")
	case "$owner" in
	age) notes="source: YubiKey bastion, ~/.secrets/$name.age" ;;
	pass) notes="source: pass, $entry" ;;
	both)
		secret_die "'$1' is in both stores; resolve the conflict first"
		return 1
		;;
	*)
		secret_die "no secret named '$1'"
		return 1
		;;
	esac
	command -v bw >/dev/null 2>&1 || {
		secret_die "bw CLI not found"
		return 1
	}
	[[ -n "${BW_SESSION:-}" ]] || {
		secret_die "Bitwarden is locked: export BW_SESSION=\$(bw unlock --raw)"
		return 1
	}
	[[ -n "$value" ]] || {
		secret_die "empty value for '$name' (read failed?); nothing sent to Bitwarden"
		return 1
	}
	desc=$(secret_desc_get "$name")
	notes="${desc:+$desc$'\n'}$notes"$'\n'"pushed $(date +%F) by secret_bw_push"
	bw sync >/dev/null 2>&1 || true # a stale cache would miss an item made elsewhere and duplicate it
	id=$(secret_bw_item_id "$name") || return 1

	if [[ -z "$id" ]]; then
		printf '%s' "$value" | jq -n --arg n "$name" --arg notes "$notes" --rawfile v /dev/stdin \
			'{type: 1, name: $n, notes: $notes, favorite: false, fields: [], reprompt: 0,
			  login: {uris: [], username: null, password: $v, totp: null}}' |
			bw encode | bw create item >/dev/null
	else
		# Fetched before the edit and checked, because an edit sends the whole item
		# back: a failed get read as an empty item would strip the username, URIs
		# and folder from the real one. Only a login item has a password to replace.
		item=$(bw get item "$id" 2>/dev/null) && [[ "$(jq -r 'select(.type == 1) | .id // empty' <<<"$item" 2>/dev/null)" == "$id" ]] || {
			unset value item
			secret_die "Bitwarden item '$name' ($id) is unreadable or not a login item; nothing changed"
			return 1
		}
		printf '%s' "$value" | jq -n --slurpfile item <(printf '%s' "$item") --arg notes "$notes" --rawfile v /dev/stdin \
			'$item[0] | .login.password = $v | .notes = $notes' |
			bw encode | bw edit item "$id" >/dev/null
	fi || {
		unset value item
		secret_die "bw could not save '$name'"
		return 1
	}
	unset value item
	# The push itself succeeded; a failed refresh only leaves the badges as they
	# were, so it warns and does not fail the push.
	secret_bw_names_refresh "$name" || true
}

# --- CLI ---------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	set -eo pipefail
	cmd="${1:-index}"
	shift || true
	case "$cmd" in
	index | locate | audit | card | read | set | create | rm | rename | promote | demote | link | unlink | refs | envrc-files | desc-get | desc-set)
		"secret_${cmd//-/_}" "$@"
		;;
	# Rebuild the Bitwarden badges by hand, with BW_SESSION exported.
	bw-refresh)
		secret_bw_names_refresh
		;;
	# Reads the value itself, so the CLI form is one command: a bastion object
	# costs its tap here exactly as Enter in the picker does.
	bw-push)
		secret_read "$1" | secret_bw_push "$1"
		;;
	*)
		printf 'usage: %s {index|locate NAME|audit|card NAME|read NAME|set NAME|rm NAME|rename OLD NEW|promote NAME|demote NAME SUB|link NAME FILE [VAR]|unlink NAME FILE|refs [NAME]|envrc-files|bw-push NAME|bw-refresh}\n\n' \
			"${0##*/}" >&2
		exit 2
		;;
	esac
fi
