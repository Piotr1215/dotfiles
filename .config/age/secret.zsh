# Bastion secret helpers (age + YubiKey).
# Reading decrypts ~/.secrets/<name>.age through the YubiKey (one physical tap, no
# PIN) and prints the value to stdout. A secret pulled this way is NEVER kept in the
# environment unless you explicitly assign it, so a rogue same-UID process cannot
# read it without your finger on the key.
#
# Source this from ~/.zshrc:   source ~/.config/age/secret.zsh
#
# Read (needs a tap):
#   sec FRED_API_KEY                                 # print value
#   export ANTHROPIC_API_ADMIN_KEY="$(sec ANTHROPIC_API_ADMIN_KEY)"   # one shell, one tap
#   curl -H "x-api-key: $(sec SOME_KEY)" ...         # inline, value never lands in env
#   sec KUBECONFIG_PROD > ~/.kube/prod               # restore a file secret
#   sec KUBECONFIG_PROD | bat                        # preview a file secret
#   sec                                              # list available bastion secrets
#
# Add a value (NO tap; encryption is public-key only):
#   secadd                                           # prompt for NAME, then the value (hidden)
#   secadd NAME                                      # prompt for the value (hidden input)
#   secadd NAME VALUE                                # value on the command line (WARNING: shell history)
#   secadd NAME --from-env                           # encrypt the current value of $NAME
#   secadd NAME --from-bw "Item" [field]             # pull from Bitwarden (default field: password)
#
# Add a file (NO tap):
#   secfile                                          # fzf-pick a file, then prompt NAME (default = filename)
#   secfile PATH                                     # take PATH, then prompt NAME (default = filename)
#   secfile PATH NAME                                # take PATH, store as NAME
#   (read a file secret back with `sec NAME` -> stdout; redirect or pipe as you like)
#
# Delete:
#   secrm NAME                                       # remove ~/.secrets/NAME.age (asks to confirm)
#
# Model: Bitwarden is the source of truth; ~/.secrets/*.age is a local,
# YubiKey-gated copy so scripts use it without plaintext in .envrc.

# Read a bastion secret to stdout (asks for a YubiKey tap). No-arg lists them.
sec() {
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
    print -u2 "sec: no bastion secret named '$name' ($f not found)"
    return 1
  fi

  # Cue the physical tap so the wait never looks like a hang.
  # Both go to stderr / the desktop, never to stdout, so $(sec ...) stays clean.
  print -u2 "sec: TOUCH your YubiKey to unlock '$name' (it is blinking) ..."
  if (( $+commands[notify-send] )); then
    ( notify-send -u normal -t 12000 "🔐 YubiKey" "Touch the key to unlock $name" >/dev/null 2>&1 & )
  fi

  age -d -i "$id" "$f"
}

# Pop an fzf file picker rooted at $HOME (used by `secfile` with no path).
# Prints the chosen absolute path to stdout; empty means cancelled.
__secret_pick_file() {
  emulate -L zsh
  (( $+commands[fzf] )) || { print -u2 "secfile: fzf not found; pass the path: secfile PATH"; return 1; }
  local -a finder
  if (( $+commands[fd] )); then
    finder=(fd --type f --hidden --follow
            --exclude .git --exclude node_modules --exclude .cache
            --exclude .local --exclude .cargo --exclude .rustup --exclude .npm
            --exclude go --exclude .var --exclude .mozilla --exclude .thunderbird
            . "$HOME")
  else
    finder=(find "$HOME" -type f)
  fi
  "${finder[@]}" 2>/dev/null | fzf --no-multi --prompt='encrypt file> ' --height=60% --reverse \
    --preview 'bat --color=always --style=plain --line-range=:200 {} 2>/dev/null || cat {}'
}

# Shared: refuse a flag-shaped name so we never write ~/.secrets/--from-file.age etc.
__secret_bad_name() {
  [[ "$1" == -* ]] && { print -u2 "$2: '$1' is not a valid name (looks like a flag)"; return 0; }
  return 1
}

# Derive a default secret name from a file path: resolve to absolute, make it
# relative to $HOME, swap '/' for '-', strip any leading '-'/'.' (which would make
# an invalid name).  ~/.kube/prod -> kube-prod ; /etc/hosts -> etc-hosts ; ./x -> <cwd>-x
__secret_name_from_path() {
  emulate -L zsh
  setopt localoptions extendedglob
  local abs="${1:a}"                 # resolve ./ and relative paths to absolute
  local p="${abs/#$HOME\//}"         # strip a leading $HOME/
  [[ "$p" == "$abs" ]] && p="${p#/}" # outside $HOME: just strip the leading /
  p="${p//\//-}"                     # / -> -
  p="${p##[-.]##}"                   # strip any leading run of '-' or '.'
  print -r -- "$p"
}

# Enroll a VALUE secret into the bastion. Encrypts to every recipient in
# ~/.config/age/recipients.txt (YubiKey + offline backup). No tap needed.
# For a whole file, use `secfile` instead.
secadd() {
  emulate -L zsh
  local recips="$HOME/.config/age/recipients.txt"
  local dir="$HOME/.secrets"
  local name="$1"

  # No name on the line -> ask for it (visible; names aren't secret).
  if [[ -z "$name" ]]; then
    print -u2 -n ">>> secret name: "
    read -r name
    [[ -n "$name" ]] || { print -u2 "secadd: no name given"; return 2; }
  fi
  __secret_bad_name "$name" secadd && return 2

  [[ -r "$recips" ]] || { print -u2 "secadd: recipients file not found ($recips)"; return 1; }
  mkdir -p "$dir" && chmod 700 "$dir"
  local out="${dir}/${name}.age"
  if [[ -e "$out" ]]; then
    print -u2 -n "secadd: $out already exists, overwrite? [y/N] "
    local ans; read -r ans
    [[ "$ans" == [yY]* ]] || { print -u2 "aborted"; return 1; }
  fi

  local val
  case "$2" in
    --from-env)
      val="${(P)name}"
      [[ -n "$val" ]] || { print -u2 "secadd: \$$name is empty or unset"; return 1; }
      ;;
    --from-bw)
      local item="$3" field="${4:-password}"
      [[ -n "$item" ]] || { print -u2 "secadd: --from-bw needs a Bitwarden item name or id (and optional field; default 'password')"; return 2; }
      (( $+commands[bw] )) || { print -u2 "secadd: bw CLI not found"; return 1; }
      case "$field" in
        password|username|notes|uri|totp)
          val="$(bw get "$field" "$item" 2>/dev/null)"
          ;;
        *)  # treat as a custom field name on the item
          (( $+commands[jq] )) || { print -u2 "secadd: jq needed to read custom field '$field'"; return 1; }
          val="$(bw get item "$item" 2>/dev/null | jq -r --arg f "$field" '.fields[]? | select(.name==$f) | .value' 2>/dev/null)"
          ;;
      esac
      [[ -n "$val" ]] || { print -u2 "secadd: nothing returned for item '$item' field '$field'. Vault locked (export BW_SESSION=\$(bw unlock --raw)), wrong item/field, or empty value."; return 1; }
      ;;
    --*)
      print -u2 "secadd: unknown option '$2' (valid: --from-env, --from-bw). For a file use: secfile PATH"
      return 2
      ;;
    "")
      print -u2 -n ">>> value for $name (input hidden, single line): "
      read -rs val
      print -u2 ""
      [[ -n "$val" ]] || { print -u2 "secadd: empty value, nothing written"; return 1; }
      ;;
    *)
      val="$2"   # value straight on the command line: secadd NAME VALUE
      ;;
  esac

  printf '%s' "$val" | age -R "$recips" -o "$out"
  unset val
  chmod 600 "$out"
  print -u2 "wrote $out  (verify with: sec $name)"
}

# Enroll a FILE as a bastion secret. Encrypts a COPY of the file to the recipients;
# the original is left in place (delete it yourself if you want only the ciphertext).
# No tap needed. Read it back like any secret: `sec NAME` streams the bytes to stdout.
#   secfile             # fzf-pick a file, then prompt NAME (default = filename)
#   secfile PATH        # take PATH, then prompt NAME (default = filename)
#   secfile PATH NAME   # take PATH, store as NAME
secfile() {
  emulate -L zsh
  local recips="$HOME/.config/age/recipients.txt"
  local dir="$HOME/.secrets"
  # NB: do NOT name this 'path' -- lowercase `path` is a special zsh array tied to
  # $PATH; a local scalar named path clobbers command lookup inside the function.
  local src="$1" name="$2"

  if [[ -z "$src" ]]; then
    src="$(__secret_pick_file)" || return 1
    [[ -n "$src" ]] || { print -u2 "secfile: no file selected"; return 1; }
  fi
  src="${src/#\~/$HOME}"
  [[ -f "$src" && -r "$src" ]] || { print -u2 "secfile: cannot read file '$src'"; return 1; }

  if [[ -z "$name" ]]; then
    local def="$(__secret_name_from_path "$src")"
    if [[ -o interactive ]]; then
      name="$def"
      vared -p '>>> secret name: ' name        # pre-filled from the path, editable
    else
      print -u2 -n ">>> secret name [$def]: "  # non-interactive (tests): plain prompt
      read -r name
    fi
    [[ -n "$name" ]] || name="$def"
  fi
  __secret_bad_name "$name" secfile && return 2

  [[ -r "$recips" ]] || { print -u2 "secfile: recipients file not found ($recips)"; return 1; }
  mkdir -p "$dir" && chmod 700 "$dir"
  local out="${dir}/${name}.age"
  if [[ -e "$out" ]]; then
    print -u2 -n "secfile: $out already exists, overwrite? [y/N] "
    local ans; read -r ans
    [[ "$ans" == [yY]* ]] || { print -u2 "aborted"; return 1; }
  fi

  age -R "$recips" -o "$out" < "$src"   # exact bytes, preserves newlines
  chmod 600 "$out"
  print -u2 "wrote $out from '$src'  (read back: sec $name > PATH  |  preview: sec $name | bat)"
}

# Remove a bastion secret (the local ~/.secrets/<name>.age copy). No tap needed.
# Bitwarden stays the source of truth for anything enrolled from there.
#   secrm NAME
secrm() {
  emulate -L zsh
  local dir="$HOME/.secrets"
  local name="$1"
  [[ -n "$name" ]] || { print -u2 "usage: secrm NAME  (list with: sec)"; return 2; }
  local f="${dir}/${name}.age"
  [[ -e "$f" ]] || { print -u2 "secrm: no bastion secret named '$name'"; return 1; }
  print -u2 -n "secrm: delete $f? [y/N] "
  local ans; read -r ans
  [[ "$ans" == [yY]* ]] || { print -u2 "aborted"; return 1; }
  rm -f -- "$f" && print -u2 "removed $name"
}

# Completion. Plain zsh completion that fzf-tab renders in its picker.
# `sec <TAB>`     -> pick from existing bastion secrets (~/.secrets/*.age)
# `secadd <TAB>`  -> pick an exported env var (handy with --from-env)
# `secfile <TAB>` -> pick a file path
if (( $+functions[compdef] )); then
  _sec() {
    local -a names
    names=(${HOME}/.secrets/*.age(N:t:r))
    (( ${#names} )) && _describe -t secrets 'bastion secret' names
  }
  compdef _sec sec
  compdef _sec secrm   # secrm NAME completes over existing secrets too

  _secadd() {
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
  compdef _secadd secadd

  _secfile() { (( CURRENT == 2 )) && _files }
  compdef _secfile secfile
fi
