#!/usr/bin/env bash
# Regression check for the secret object model (scripts/__lib_secret_object.sh).
#
# Isolated fake HOME with a throwaway age key used as BOTH recipient and
# identity, so every bastion read here decrypts with no YubiKey and no tap, and a
# stub `pass` so no GPG key is needed either. The stub stores entries as
# plaintext .gpg files, which is all this suite needs: what is under test is the
# object model (who owns a value, which references follow it), not gpg.
set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)"
T="/tmp/secobj.$$"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T"/{.secrets,bin,proj,other}
mkdir -p "$T/.password-store/personal" "$T/.password-store/work"
mkdir -p "$T/allow"

age-keygen -o "$T/key.txt" 2>/dev/null
grep 'public key' "$T/key.txt" | sed 's/.*: //' >"$T/recipients.txt"

cat >"$T/bin/pass" <<'EOF'
#!/usr/bin/env bash
# Minimal pass stub: entries are plaintext files under $PASSWORD_STORE_DIR.
store="$PASSWORD_STORE_DIR"
cmd="$1"; shift
while [[ "${1:-}" == -* ]]; do shift; done
case "$cmd" in
show)   cat "$store/$1.gpg" ;;
mv)     mkdir -p "$store/$(dirname "$2")"; mv "$store/$1.gpg" "$store/$2.gpg" ;;
insert) mkdir -p "$store/$(dirname "$1")"; cat >"$store/$1.gpg" ;;
rm)     rm -f "$store/$1.gpg" ;;
*)      exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/direnv"
chmod +x "$T/bin/pass" "$T/bin/direnv"
PATH="$T/bin:$PATH"

export SECRETS_DIR="$T/.secrets"
export PASSWORD_STORE_DIR="$T/.password-store"
export AGE_ID="$T/key.txt"
export AGE_RECIPIENTS="$T/recipients.txt"
export DIRENV_ALLOW_DIR="$T/allow"

# shellcheck source=/dev/null
source "$SCRIPTS/__lib_secret_object.sh"

pass_n=0
fail_n=0
ok() {
	printf '  ok   %s\n' "$1"
	((pass_n++))
	return 0
}
bad() {
	printf '  FAIL %s\n' "$1"
	((fail_n++))
	return 0
}
is() { [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (got [$2] want [$3])"; }
field() { secret_locate "$1" | cut -f"$2"; }

# --- fixtures ----------------------------------------------------------------
printf 'aval' | secret_write_age A_ONLY
printf 'aval' | secret_write_age A_DEMO
printf 'pval' | secret_write_pass work/P_ONLY
printf 'lval' | secret_write_pass personal/P_LINK
printf 'rval' | secret_write_pass work/P_PROMO
printf 'dval' | secret_write_pass work/P_DEL
printf 'bval' | secret_write_age BOTH
printf 'bval' | secret_write_pass work/BOTH

cat >"$T/proj/.envrc" <<EOF
export UNRELATED=1
_pass_export P_ONLY work/P_ONLY
_pass_export RENAMED_VAR work/P_PROMO
_pass_export P_DEL work/P_DEL
_pass_export GONE work/GONE
EOF
printf '%s\n' "$T/proj/.envrc" >"$T/allow/one"
printf '%s\n' "$T/other/.envrc" >"$T/allow/two"
: >"$T/other/.envrc"

echo "== the object and its stores =="
is "bastion-only secret is owned by age" "$(field A_ONLY 2)" "age"
is "pass secret is owned by pass" "$(field P_ONLY 2)" "pass"
is "pass secret carries its entry path" "$(field P_ONLY 3)" "work/P_ONLY"
is "references are counted per object" "$(field P_ONLY 4)" "1"
is "a reference under a different var name still counts" "$(field P_PROMO 4)" "1"
is "an unreferenced secret has no refs" "$(field P_LINK 4)" "0"

echo "== creating an object chooses exactly one store =="
printf 'created-pass' | secret_create P_CREATED pass work
is "create writes a pass secret into the chosen subtree" "$(secret_read P_CREATED)" "created-pass"
is "a created pass secret has one owner" "$(field P_CREATED 3)" "work/P_CREATED"
printf 'created-age' | secret_create A_CREATED age
is "create writes a bastion secret" "$(secret_read A_CREATED)" "created-age"
is "a created bastion secret has one owner" "$(field A_CREATED 2)" "age"
printf 'replacement' | secret_create P_CREATED age 2>/dev/null
is "create refuses an existing name" "$(secret_read P_CREATED)" "created-pass"
printf 'bad-name' | secret_create 'BAD NAME' pass work 2>/dev/null
is "create refuses an invalid name" "$(field 'BAD NAME' 2)" ""

echo "== the invariant =="
is "a name in both stores is a conflict" "$(field BOTH 5)" "conflict"
is "a reference with no entry behind it dangles" "$(field GONE 5)" "dangling"
is "a healthy object is ok" "$(field P_ONLY 5)" "ok"
is "audit reports exactly the broken ones" \
	"$(secret_audit | cut -f1 | sort | tr '\n' ' ')" "BOTH GONE "

echo "== value writes go to the owning store, and only there =="
printf 'rotated' | secret_set P_ONLY
is "rotating a pass secret writes pass" "$(secret_read P_ONLY)" "rotated"
is "rotating a pass secret leaves no bastion copy" \
	"$([ -e "$T/.secrets/P_ONLY.age" ] && echo yes || echo no)" "no"
printf 'rotated' | secret_set A_ONLY
is "rotating a bastion secret writes the bastion" "$(secret_read A_ONLY)" "rotated"
printf 'nope' | secret_set BOTH 2>/dev/null
is "a conflicted object refuses a write" "$(pass show work/BOTH)" "bval"

echo "== store 3 is a reference, and requires store 2 =="
secret_link P_LINK "$T/other/.envrc"
is "link defaults the variable to the object name" \
	"$(cat "$T/other/.envrc")" "_pass_export P_LINK personal/P_LINK"
is "the new reference is visible to the index" "$(field P_LINK 4)" "1"
secret_link P_LINK "$T/other/.envrc"
is "linking twice does not export it twice" "$(wc -l <"$T/other/.envrc")" "1"
secret_link A_ONLY "$T/other/.envrc" 2>/dev/null
is "a bastion secret cannot be referenced" "$(wc -l <"$T/other/.envrc")" "1"
secret_unlink P_LINK "$T/other/.envrc"
is "unlinking store 3 leaves store 2 alone" "$(secret_read P_LINK)" "lval"

echo "== deleting from store 2 takes store 3 with it =="
secret_rm P_DEL
is "the pass entry is gone" "$(field P_DEL 2)" ""
is "its reference is gone too" "$(grep -c P_DEL "$T/proj/.envrc")" "0"
is "other references in the same file survive" "$(grep -c '^_pass_export' "$T/proj/.envrc")" "3"

echo "== tier moves =="
secret_desc_set P_PROMO "promoted secret"
secret_promote P_PROMO
is "promote lands the value in the bastion" "$(secret_read P_PROMO)" "rval"
is "promote is a move, not a copy" "$(field P_PROMO 2)" "age"
is "promote drops the .envrc reference" "$(grep -c RENAMED_VAR "$T/proj/.envrc")" "0"
is "the description survives the move" "$(secret_desc_get P_PROMO)" "promoted secret"

secret_demote A_DEMO work
is "demote lands the value in pass" "$(secret_read A_DEMO)" "aval"
is "demote picks the named subtree" "$(field A_DEMO 3)" "work/A_DEMO"
is "demote removes the bastion copy" \
	"$([ -e "$T/.secrets/A_DEMO.age" ] && echo yes || echo no)" "no"
secret_demote P_ONLY work 2>/dev/null
is "demoting something already in pass is refused" "$(field P_ONLY 2)" "pass"

echo "== renaming carries the identity everywhere =="
printf 'mval' | secret_write_pass work/P_RENAME
cat >>"$T/proj/.envrc" <<EOF
_pass_export P_RENAME work/P_RENAME
_pass_export LEGACY_NAME work/P_RENAME
EOF
secret_desc_set P_RENAME "renamed secret"
is "the same entry can be exported twice under different names" "$(field P_RENAME 4)" "2"
secret_rename P_RENAME P_RENAMED
is "the value survives the rename" "$(secret_read P_RENAMED)" "mval"
is "the entry moved inside its subtree" "$(field P_RENAMED 3)" "work/P_RENAMED"
is "references follow the new entry" "$(field P_RENAMED 4)" "2"
is "a var that matched the old name follows it" \
	"$(grep -c '^_pass_export P_RENAMED work/P_RENAMED$' "$T/proj/.envrc")" "1"
is "a deliberately different var is left alone" \
	"$(grep -c '^_pass_export LEGACY_NAME work/P_RENAMED$' "$T/proj/.envrc")" "1"
is "the description follows the rename" "$(secret_desc_get P_RENAMED)" "renamed secret"
is "nothing is left under the old name" "$(field P_RENAME 2)" ""
secret_rename P_RENAMED P_ONLY 2>/dev/null
is "renaming onto an existing name is refused" "$(field P_RENAMED 3)" "work/P_RENAMED"
secret_rename A_ONLY A_RENAMED
is "a bastion secret renames too" "$(secret_read A_RENAMED)" "rotated"

echo "== references are line-addressed =="
is "each reference reports its own line" \
	"$(secret_refs P_RENAMED | cut -f2 | tr '\n' ' ')" "$(grep -n '_pass_export .* work/P_RENAMED$' "$T/proj/.envrc" | cut -d: -f1 | tr '\n' ' ')"

echo "== a failed read never writes =="
printf 'gval' | secret_write_age A_GUARD
real_age_id="$AGE_ID"
export AGE_ID="$T/no-such-identity.txt"
secret_demote A_GUARD personal 2>/dev/null
is "a failed decrypt writes no pass entry" \
	"$([ -e "$T/.password-store/personal/A_GUARD.gpg" ] && echo yes || echo no)" "no"
is "and leaves the bastion copy where it was" \
	"$([ -e "$T/.secrets/A_GUARD.age" ] && echo yes || echo no)" "yes"
export AGE_ID="$real_age_id"
is "the secret is still readable afterwards" "$(secret_read A_GUARD)" "gval"

: >"$T/.password-store/work/P_EMPTY.gpg"
secret_promote P_EMPTY 2>/dev/null
is "promoting an empty entry writes no bastion copy" \
	"$([ -e "$T/.secrets/P_EMPTY.age" ] && echo yes || echo no)" "no"

echo "== multi-line values survive every path =="
# Regression. secret_read truncated pass entries to line 1, so a PEM came back
# as its BEGIN marker, and promote wrote that truncation into the bastion and
# then deleted the original. demote used to refuse multi-line for the same
# reason; the writer was always `pass insert -m`, so only the reader was wrong.
multi=$'-----BEGIN PRIVATE KEY-----\nMIIsecret\n-----END PRIVATE KEY-----'
printf '%s' "$multi" | secret_write_pass personal/P_MULTI
is "a multi-line pass secret reads back whole" "$(secret_read P_MULTI)" "$multi"
secret_promote P_MULTI
is "promote keeps every line" "$(secret_read P_MULTI)" "$multi"
is "promote moved it to the bastion" "$(field P_MULTI 2)" "age"

printf '%s' "$multi" | secret_write_age A_MULTI
secret_demote A_MULTI personal
is "a multi-line secret demotes into pass" \
	"$([ -e "$T/.password-store/personal/A_MULTI.gpg" ] && echo yes || echo no)" "yes"
is "demote keeps every line" "$(secret_read A_MULTI)" "$multi"

printf '\n%d passed, %d failed\n' "$pass_n" "$fail_n"
((fail_n == 0))
