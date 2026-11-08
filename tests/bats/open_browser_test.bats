#!/usr/bin/env bats
#
# BROWSER must name the mode-aware launcher, not a fixed browser. On 8 Nov an
# `aws sso login` opened LibreWolf in work mode: .zprofile had baked
# BROWSER=librewolf into every shell at login, and `ufp work` only fixed the
# one shell it ran in. Chrome was never consulted. google-chrome and flatpak are
# stubs, and the mode flag is a temp file, so no test opens a real browser.

setup() {
  root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  launcher="$root/scripts/__open_browser.sh"
  export TIMEOFF_MODE_FILE="$BATS_TEST_TMPDIR/timeoff_mode" LOG="$BATS_TEST_TMPDIR/log"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  for exe in google-chrome flatpak; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" %s "$@" >> "$LOG"\n' "$exe" > "$BATS_TEST_TMPDIR/bin/$exe"
    chmod +x "$BATS_TEST_TMPDIR/bin/$exe"
  done
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test ".zprofile points BROWSER at the launcher in work and home mode" {
  for mode in work home; do
    [ "$mode" = home ] && touch "$TIMEOFF_MODE_FILE"
    run env -i HOME="$BATS_TEST_TMPDIR" TIMEOFF_MODE_FILE="$TIMEOFF_MODE_FILE" \
      zsh -fc "source '$root/.zprofile'; print -r -- \$BROWSER"
    [ "$status" -eq 0 ]
    [ "$output" = "$BATS_TEST_TMPDIR/dev/dotfiles/scripts/__open_browser.sh" ]
  done
}

@test "ufp work and ufp home both leave BROWSER on the launcher and flip the mode flag" {
  for exe in xdg-settings tmux __tmux_active_task.sh; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" %s "$@" >> "$LOG"\n' "$exe" > "$BATS_TEST_TMPDIR/bin/$exe"
    chmod +x "$BATS_TEST_TMPDIR/bin/$exe"
  done
  awk '/^function ufp\(\) \{/,/^}/' "$root/.zsh_functions" > "$BATS_TEST_TMPDIR/ufp.zsh"
  run env HOME="$BATS_TEST_TMPDIR" zsh -fc "source '$BATS_TEST_TMPDIR/ufp.zsh'
    ufp home >/dev/null; print -r -- \"home \$BROWSER \$([[ -f \$TIMEOFF_MODE_FILE ]] && echo flag)\"
    ufp work >/dev/null; print -r -- \"work \$BROWSER \$([[ -f \$TIMEOFF_MODE_FILE ]] && echo flag)\""
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "home $BATS_TEST_TMPDIR/dev/dotfiles/scripts/__open_browser.sh flag" ]
  [ "${lines[1]}" = "work $BATS_TEST_TMPDIR/dev/dotfiles/scripts/__open_browser.sh " ]
}

@test "work mode opens the URL in Chrome's loft.sh profile" {
  run "$launcher" https://example.com/login
  [ "$status" -eq 0 ]
  mapfile -t args < "$LOG"
  [ "${args[*]}" = "google-chrome --profile-directory=Profile 1 https://example.com/login" ]
}

@test "home mode opens the URL in LibreWolf's Home profile" {
  touch "$TIMEOFF_MODE_FILE"
  run "$launcher" https://example.com/login
  [ "$status" -eq 0 ]
  mapfile -t args < "$LOG"
  [ "${args[*]}" = "flatpak run io.gitlab.librewolf-community -P Home https://example.com/login" ]
}

@test "a client that honours BROWSER, as the aws cli does, reaches the launcher" {
  run env BROWSER="$launcher" python3 -I -c 'import webbrowser; webbrowser.open("https://example.com/sso")'
  [ "$status" -eq 0 ]
  mapfile -t args < "$LOG"
  [ "${args[*]}" = "google-chrome --profile-directory=Profile 1 https://example.com/sso" ]
}
