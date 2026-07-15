# Password-store helpers.
#
# Companion to ~/.config/age/secret.zsh, NOT a replacement. Two tiers, two threats:
#
#   pass     secrets a session needs for its whole life; direnv resolves them on cd.
#            No gate, because the value lands in the environment anyway and a tap
#            there would buy nothing. The win is no plaintext at rest in an .envrc,
#            so the file stays committable and never leaks via git/backup/screenshare.
#
#   bastion  ad-hoc secrets (`sec NAME`). One YubiKey tap per read, never exported.
#            The only layer that survives a rogue process running as you.
#
# Source this from ~/.zshrc:   source ~/.config/pass/pass.zsh
#
#   passadd NAME                  # $NAME -> personal/NAME
#   passadd NAME --store=work     # $NAME -> work/NAME
#
# Store layout: each subdir can pin its own key via .gpg-id, so work/ encrypts to
# the Loft key and everything else to the personal one. `pass init -p <dir> <FPR>`
# sets that up. Always pin a FULL FINGERPRINT, never an email: two of the keys on
# this machine carry piotrzan@gmail.com, and GPG silently picks one of them.

# Enroll an EXPORTED env var into the password store.
#
# Takes the variable NAME, not $NAME. `passadd FOO` reads $FOO out of the
# environment, so the value never touches the command line and so never lands in
# zsh history (this machine has hist_ignore_space unset, .zshrc:94).
passadd() {
  emulate -L zsh
  local store="personal"
  local -a rest=()

  while (( $# )); do
    case "$1" in
      --store=*) store="${1#--store=}"; shift ;;
      --store)
        (( $# >= 2 )) || { print -u2 "passadd: --store needs a value (e.g. --store=work)"; return 2 }
        store="$2"; shift 2 ;;
      --) shift; rest+=("$@"); break ;;
      -*) print -u2 "passadd: unknown option '$1' (valid: --store=<dir>)"; return 2 ;;
      *) rest+=("$1"); shift ;;
    esac
  done
  set -- "${rest[@]}"
  local name="$1"

  [[ -n "$name" ]] || {
    print -u2 "usage: passadd NAME [--store=work|personal]"
    print -u2 "       NAME is the variable name, not \$NAME (the value comes from the environment)"
    return 2
  }
  # Refuse a flag-shaped name so a typo can never write personal/--store.gpg.
  [[ "$name" == -* ]] && { print -u2 "passadd: '$name' is not a valid name (looks like a flag)"; return 2 }

  local dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
  store="${store%/}"
  [[ -d "$dir/$store" ]] || {
    print -u2 "passadd: no store '$store' in $dir. Available:"
    print -l -u2 -- ${dir}/*(/N:t)
    return 1
  }

  # (P) dereferences the name to its value, same trick `secadd --from-env` uses.
  local val="${(P)name}"
  [[ -n "$val" ]] || { print -u2 "passadd: \$$name is empty or unset (export it first)"; return 1 }

  local target="${store}/${name}"

  # Prompt for the overwrite ourselves. `pass insert` prompts too, but it reads
  # the answer from stdin, which is exactly where the secret is arriving, so it
  # would swallow the first line of the value as the y/n answer. Hence -f below.
  if [[ -e "$dir/${target}.gpg" ]]; then
    print -u2 -n "passadd: $target already exists, overwrite? [y/N] "
    local ans; read -r ans
    [[ "$ans" == [yY]* ]] || { print -u2 "aborted"; return 1 }
  fi

  # Trailing newline matches what plain `pass insert` stores, so entries added
  # either way read back identically through `pass show` and $(pass show ...).
  if printf '%s\n' "$val" | pass insert -m -f "$target" >/dev/null 2>&1; then
    unset val
    print -u2 "wrote $target  (verify with: pass show $target)"
    print -u2 "  .envrc:  export ${name}=\"\$(pass show ${target})\""
  else
    unset val
    print -u2 "passadd: pass insert failed for $target"
    return 1
  fi
}

# Completion: NAME slot lists exported env vars, later slots offer the real
# stores found on disk, so a typo'd --store=wrok never silently makes a dir.
if (( $+functions[compdef] )); then
  _passadd() {
    local dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
    if (( CURRENT == 2 )); then
      local -a exported; local k
      for k in ${(k)parameters}; do
        [[ ${(Pt)k} == *export* ]] && exported+=$k
      done
      (( ${#exported} )) && _describe -t env-vars 'exported env var' exported
    else
      local -a opts=(); local s
      for s in ${dir}/*(/N:t); do opts+=("--store=$s"); done
      (( ${#opts} )) && _describe -t stores 'store' opts
    fi
  }
  compdef _passadd passadd
fi
