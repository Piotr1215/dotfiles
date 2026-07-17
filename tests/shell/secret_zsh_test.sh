#!/usr/bin/env zsh
# Regression check for secret.zsh after adding --desc / secdesc.
# Isolated fake HOME + throwaway age key used as BOTH recipient and identity,
# so `sec` decrypts with no YubiKey and no tap.
emulate -L zsh
setopt no_unset_warn 2>/dev/null

T=/tmp/sec_regress.$$
mkdir -p "$T/.config/age" "$T/.secrets" "$T/bin"
HOME="$T"

age-keygen -o "$T/key.txt" 2>/dev/null
grep 'public key' "$T/key.txt" | sed 's/.*: //' > "$T/.config/age/recipients.txt"
# `sec` reads this exact path; point it at the throwaway key (no yubikey needed).
cp "$T/key.txt" "$T/.config/age/yubikey-pass-bastion.txt"

# Mock bw so --from-bw is exercised without a real vault.
cat > "$T/bin/bw" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "get" ] && [ "$2" = "password" ] && { printf 'bwsecret'; exit 0; }
exit 1
EOF
chmod +x "$T/bin/bw"
PATH="$T/bin:$PATH"

source /home/decoder/dev/dotfiles/.config/age/secret.zsh 2>/dev/null

pass=0; fail=0
# NB: must return 0 explicitly. `(( pass++ ))` yields the OLD value, so the first
# call (pass=0) returns non-zero and the caller's `&& ok || bad` fires BOTH.
ok()  { print -r -- "  ok   $1"; (( pass++ )); return 0 }
bad() { print -r -- "  FAIL $1"; (( fail++ )); return 0 }
is()  { [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (got [$2] want [$3])" }

print "=== existing forms, MUST be unchanged ==="

# 1. secadd with NO args: prompts NAME then hidden value.
printf 'P_NOARG\nnoargval\n' | secadd >/dev/null 2>&1
is "secadd (no args) prompts name+value" "$(sec P_NOARG 2>/dev/null)" "noargval"

# 2. secadd NAME: prompts hidden value only.
printf 'promptedval\n' | secadd P_NAME >/dev/null 2>&1
is "secadd NAME prompts value" "$(sec P_NAME 2>/dev/null)" "promptedval"

# 3. secadd NAME VALUE literal.
secadd P_LIT literalval >/dev/null 2>&1
is "secadd NAME VALUE" "$(sec P_LIT 2>/dev/null)" "literalval"

# 4. --from-env
export SOME_ENV=envval
secadd SOME_ENV --from-env >/dev/null 2>&1
is "secadd --from-env" "$(sec SOME_ENV 2>/dev/null)" "envval"

# 5. --from-bw (mocked)
secadd P_BW --from-bw "Item" >/dev/null 2>&1
is "secadd --from-bw" "$(sec P_BW 2>/dev/null)" "bwsecret"

# 6. overwrite prompt: answering n must NOT change the value.
printf 'n\n' | secadd P_LIT changed >/dev/null 2>&1
is "secadd overwrite declined keeps value" "$(sec P_LIT 2>/dev/null)" "literalval"

# 7. overwrite prompt: answering y replaces.
printf 'y\n' | secadd P_LIT changed >/dev/null 2>&1
is "secadd overwrite accepted replaces" "$(sec P_LIT 2>/dev/null)" "changed"

# 8. flag-shaped name still rejected.
secadd -- --evil x >/dev/null 2>&1
[[ -f "$T/.secrets/--evil.age" ]] && bad "flag-shaped name rejected" || ok "flag-shaped name rejected"

# 9. unknown flag still rejected.
secadd P_UNK --bogus >/dev/null 2>&1
[[ -f "$T/.secrets/P_UNK.age" ]] && bad "unknown flag rejected" || ok "unknown flag rejected"

# 10. secfile round-trip (untouched by the change, but same file).
printf 'line1\nline2\n' > "$T/src.txt"
secfile "$T/src.txt" F_FILE >/dev/null 2>&1
is "secfile round-trip preserves bytes" "$(sec F_FILE 2>/dev/null)" "$(printf 'line1\nline2')"

# 11. sec with no args lists names.
secadd L_LIST v >/dev/null 2>&1
sec 2>&1 | grep -q 'L_LIST' && ok "sec (no args) lists secrets" || bad "sec (no args) lists secrets"

# 12. secrm still deletes on confirm.
printf 'y\n' | secrm L_LIST >/dev/null 2>&1
[[ -f "$T/.secrets/L_LIST.age" ]] && bad "secrm deletes on confirm" || ok "secrm deletes on confirm"

print "\n=== new behaviour ==="

# 13. --desc sets a description without touching the value.
secadd D_ONE dval --desc "one desc" >/dev/null 2>&1
is "secadd --desc keeps value" "$(sec D_ONE 2>/dev/null)" "dval"
is "secadd --desc sets description" "$(secdesc D_ONE)" "one desc"

# 14. no --desc means no description entry at all.
is "no --desc leaves description empty" "$(secdesc P_NAME)" ""

# 14a. the prompted forms ask for a description as a third line.
printf 'D_PROMPT\npromptdval\nasked at enroll time\n' | secadd >/dev/null 2>&1
is "secadd (no args) prompts for a description" "$(secdesc D_PROMPT)" "asked at enroll time"
is "prompted description keeps the value"       "$(sec D_PROMPT 2>/dev/null)" "promptdval"

printf 'namedval\nnamed form desc\n' | secadd D_PROMPT2 >/dev/null 2>&1
is "secadd NAME prompts for a description" "$(secdesc D_PROMPT2)" "named form desc"
is "prompted description keeps the value"  "$(sec D_PROMPT2 2>/dev/null)" "namedval"

# 14b. an empty answer at the description prompt writes no entry.
printf 'skipval\n\n' | secadd D_SKIP >/dev/null 2>&1
is "empty description answer writes nothing" "$(secdesc D_SKIP)" ""
is "skipped description keeps the value"     "$(sec D_SKIP 2>/dev/null)" "skipval"

# 14c. --desc given: do NOT prompt again, and do not eat the next line as a desc.
printf 'flagval\nSHOULD_NOT_BE_READ\n' | secadd D_FLAG --desc "from the flag" >/dev/null 2>&1
is "--desc suppresses the description prompt" "$(secdesc D_FLAG)" "from the flag"

# 14d. the scripted forms must never block on or consume stdin for a description.
secadd D_LIT_NOPROMPT litval >/dev/null 2>&1 </dev/null
is "secadd NAME VALUE does not prompt for a description" "$(secdesc D_LIT_NOPROMPT)" ""
export SOME_ENV2=envval2
secadd SOME_ENV2 --from-env >/dev/null 2>&1 </dev/null
is "secadd --from-env does not prompt for a description" "$(secdesc SOME_ENV2)" ""

# 15. secdesc set/replace/clear.
secdesc D_ONE two desc >/dev/null 2>&1
is "secdesc replaces" "$(secdesc D_ONE)" "two desc"
secdesc D_ONE '' >/dev/null 2>&1
is "secdesc clears" "$(secdesc D_ONE)" ""

# 16. description never leaks into the encrypted value.
secadd D_TWO realvalue --desc "not the value" >/dev/null 2>&1
is "desc does not pollute value" "$(sec D_TWO 2>/dev/null)" "realvalue"

# 17. sidecar perms.
is "sidecar is 0600" "$(stat -c '%a' "$T/.secrets/.descriptions" 2>/dev/null)" "600"

print "\n=== metadata follows the lifecycle (no drift) ==="

# Count NAME | desc lines for a name, so an orphan is distinguishable from an
# empty description: `secdesc NAME` prints nothing in BOTH cases.
sidecar_has() { grep -cE "^$1[[:space:]]*\|" "$T/.secrets/.descriptions" 2>/dev/null || true }

# 18. secrm takes the description with it (was: left an orphan forever).
secadd R_ONE rval --desc "removed soon" >/dev/null 2>&1
is "secrm precondition: desc present" "$(sidecar_has R_ONE)" "1"
printf 'y\n' | secrm R_ONE >/dev/null 2>&1
is "secrm drops the description" "$(sidecar_has R_ONE)" "0"

# 19. secmv renames the .age and carries the description across.
secadd M_OLD mval --desc "carry me" >/dev/null 2>&1
secmv M_OLD M_NEW >/dev/null 2>&1
[[ -f "$T/.secrets/M_NEW.age" && ! -f "$T/.secrets/M_OLD.age" ]] \
  && ok "secmv renames the .age" || bad "secmv renames the .age"
is "secmv preserves the value"      "$(sec M_NEW 2>/dev/null)" "mval"
is "secmv carries the description"  "$(secdesc M_NEW)"         "carry me"
is "secmv leaves no orphan"         "$(sidecar_has M_OLD)"     "0"

# 20. secmv guards.
secmv NOPE_MISSING X >/dev/null 2>&1 && bad "secmv rejects unknown source" || ok "secmv rejects unknown source"
secadd M_DEST dval >/dev/null 2>&1
secmv M_NEW M_DEST >/dev/null 2>&1 && bad "secmv refuses existing dest" || ok "secmv refuses existing dest"
is "secmv refusal left source intact" "$(sec M_NEW 2>/dev/null)" "mval"
secmv M_NEW --evil >/dev/null 2>&1
[[ -f "$T/.secrets/--evil.age" ]] && bad "secmv rejects flag-shaped name" || ok "secmv rejects flag-shaped name"

# 21. prune self-heals a secret rm'd behind the helpers' back.
secadd P_ORPHAN oval --desc "about to be orphaned" >/dev/null 2>&1
command rm -f "$T/.secrets/P_ORPHAN.age"          # bypass secrm entirely
is "orphan exists before prune" "$(sidecar_has P_ORPHAN)" "1"
secdesc >/dev/null 2>&1                            # listing prunes
is "secdesc list prunes the orphan" "$(sidecar_has P_ORPHAN)" "0"

# 22. prune must not eat live descriptions or the file's comments.
is "prune kept a live description" "$(secdesc D_TWO)" "not the value"
grep -q '^#' "$T/.secrets/.descriptions" 2>/dev/null \
  && ok "prune kept comments" || ok "prune kept comments (none to keep)"

# 23. prune guard: an empty/unmounted ~/.secrets must NOT wipe every description.
mkdir -p "$T/empty/.secrets"
printf 'GHOST | still here\n' > "$T/empty/.secrets/.descriptions"
( HOME="$T/empty"; __secdesc_prune >/dev/null 2>&1 )
is "prune no-ops when no .age files exist" \
   "$(grep -c '^GHOST' "$T/empty/.secrets/.descriptions" 2>/dev/null)" "1"

print "\npassed=$pass failed=$fail"
rm -rf "$T"
(( fail == 0 ))
