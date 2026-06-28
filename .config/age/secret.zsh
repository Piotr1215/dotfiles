# Bastion secret fetch.
# Decrypts ~/.secrets/<name>.age through the YubiKey (one physical tap, no PIN)
# and prints the value to stdout. A secret pulled this way is NEVER kept in the
# environment unless you explicitly assign it, so a rogue same-UID process cannot
# read it without your finger on the key.
#
# Source this from ~/.zshrc:   source ~/.config/age/secret.zsh
#
# Usage:
#   secret FRED_API_KEY                              # print value (asks for a tap)
#   export ANTHROPIC_API_ADMIN_KEY="$(secret ANTHROPIC_API_ADMIN_KEY)"   # one shell, one tap
#   curl -H "x-api-key: $(secret SOME_KEY)" ...      # inline, value never lands in env
#   secret                                           # list available bastion secrets
#
#   secret-add ANTHROPIC_API_ADMIN_KEY --from-env    # encrypt the current $ANTHROPIC_API_ADMIN_KEY
#   secret-add ANTHROPIC_API_ADMIN_KEY --from-bw "Anthropic admin"          # default field: password
#   secret-add SOME_KEY --from-bw "My Secure Note" notes                    # pull from notes
#   secret-add SOME_KEY --from-bw "Login item" apikey                       # pull a custom field named apikey
#   secret-add SOME_NEW_KEY                           # prompt for the value (hidden input)
#   (creating needs NO tap: encryption is public-key only)
#
# Model: Bitwarden is the source of truth; ~/.secrets/*.age is a local,
# YubiKey-gated copy so scripts use it without plaintext in .envrc.

secret() {
  emulate -L zsh
  local id="$HOME/.config/age/yubikey-pass-bastion.txt"
  local dir="$HOME/.secrets"
  local name="$1"

  if [[ -z "$name" ]]; then
    print -u2 "bastion secrets available (need a YubiKey tap to read):"
    print -l -u2 -- ${dir}/*.age(N:t:r)
    return 2
  fi

  local f="${dir}/${name}.age"
  if [[ ! -r "$f" ]]; then
    print -u2 "secret: no bastion secret named '$name' ($f not found)"
    return 1
  fi

  # Cue the physical tap so the wait never looks like a hang.
  # Both go to stderr / the desktop, never to stdout, so $(secret ...) stays clean.
  print -u2 "secret: TOUCH your YubiKey to unlock '$name' (it is blinking) ..."
  if (( $+commands[notify-send] )); then
    ( notify-send -u normal -t 12000 "🔐 YubiKey" "Touch the key to unlock $name" >/dev/null 2>&1 & )
  fi

  age -d -i "$id" "$f"
}

# Enroll a secret into the bastion. Encrypts to every recipient in
# ~/.config/age/recipients.txt (YubiKey + offline backup). No tap needed.
#   secret-add NAME --from-env   # encrypt the current value of $NAME
#   secret-add NAME              # prompt for the value with hidden input
secret-add() {
  emulate -L zsh
  local recips="$HOME/.config/age/recipients.txt"
  local dir="$HOME/.secrets"
  local name="$1"

  if [[ -z "$name" ]]; then
    print -u2 "usage: secret-add NAME [--from-env]"
    return 2
  fi
  if [[ ! -r "$recips" ]]; then
    print -u2 "secret-add: recipients file not found ($recips)"
    return 1
  fi

  mkdir -p "$dir" && chmod 700 "$dir"
  local out="${dir}/${name}.age"
  if [[ -e "$out" ]]; then
    print -u2 -n "secret-add: $out already exists, overwrite? [y/N] "
    local ans; read -r ans
    [[ "$ans" == [yY]* ]] || { print -u2 "aborted"; return 1; }
  fi

  local val
  case "$2" in
    --from-env)
      val="${(P)name}"
      [[ -n "$val" ]] || { print -u2 "secret-add: \$$name is empty or unset"; return 1; }
      ;;
    --from-bw)
      local item="$3" field="${4:-password}"
      [[ -n "$item" ]] || { print -u2 "secret-add: --from-bw needs a Bitwarden item name or id (and optional field; default 'password')"; return 2; }
      (( $+commands[bw] )) || { print -u2 "secret-add: bw CLI not found"; return 1; }
      case "$field" in
        password|username|notes|uri|totp)
          val="$(bw get "$field" "$item" 2>/dev/null)"
          ;;
        *)  # treat as a custom field name on the item
          (( $+commands[jq] )) || { print -u2 "secret-add: jq needed to read custom field '$field'"; return 1; }
          val="$(bw get item "$item" 2>/dev/null | jq -r --arg f "$field" '.fields[]? | select(.name==$f) | .value' 2>/dev/null)"
          ;;
      esac
      [[ -n "$val" ]] || { print -u2 "secret-add: nothing returned for item '$item' field '$field'. Vault locked (export BW_SESSION=\$(bw unlock --raw)), wrong item/field, or empty value."; return 1; }
      ;;
    *)
      print -u2 -n ">>> value for $name (input hidden, single line): "
      read -rs val
      print -u2 ""
      [[ -n "$val" ]] || { print -u2 "secret-add: empty value, nothing written"; return 1; }
      ;;
  esac

  printf '%s' "$val" | age -R "$recips" -o "$out"
  unset val
  chmod 600 "$out"
  print -u2 "wrote $out  (verify with: secret $name)"
}

# Completion. Plain zsh completion that fzf-tab renders in its picker.
# `secret <TAB>`     -> pick from existing bastion secrets (~/.secrets/*.age)
# `secret-add <TAB>` -> pick an exported env var (handy with --from-env)
if (( $+functions[compdef] )); then
  _secret() {
    local -a names
    names=(${HOME}/.secrets/*.age(N:t:r))
    (( ${#names} )) && _describe -t secrets 'bastion secret' names
  }
  compdef _secret secret

  _secret_add() {
    if (( CURRENT == 2 )); then
      local -a exported; local k
      for k in ${(k)parameters}; do
        [[ ${(Pt)k} == *export* ]] && exported+=$k
      done
      (( ${#exported} )) && _describe -t env-vars 'exported env var' exported
    elif (( CURRENT == 3 )); then
      _values 'option' '--from-env' '--from-bw'
    elif (( CURRENT == 4 )) && [[ ${words[3]} == --from-bw ]]; then
      _values 'bitwarden field' password username notes uri totp
    fi
  }
  compdef _secret_add secret-add
fi
