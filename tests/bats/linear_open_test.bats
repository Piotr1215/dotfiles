#!/usr/bin/env bats

# __linear_open.sh is the ctrl+4 Alacritty hint target. LINEAR_OPEN_DRYRUN
# prints the url it would open, and a scratch HOME with a cached team list keeps
# the Linear branch off the network.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__linear_open.sh"
  ALACRITTY="${BATS_TEST_DIRNAME}/../../.config/alacritty/alacritty.toml"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME/.cache/linear"
  printf 'DEVOPS\n' > "$HOME/.cache/linear/team-keys"
  export LINEAR_OPEN_DRYRUN=1
}

# The ctrl+4 hint regex, read from the live Alacritty config.
hint_regex() {
  awk '/^binding = \{ key = "4"/ { print re; exit } /^regex = / { re = $0 }' "$ALACRITTY" |
    sed -e 's/^regex = "//' -e 's/"$//'
}

@test "an owner/repo#N ref opens that pull request" {
  run "$SCRIPT" 'Piotr1215/claude#9'
  [ "$status" -eq 0 ]
  [ "$output" = 'OPEN https://github.com/Piotr1215/claude/pull/9' ]
}

@test "a repo#N ref with no owner opens the loft-sh pull request" {
  run "$SCRIPT" 'vcluster-docs#1234'
  [ "$status" -eq 0 ]
  [ "$output" = 'OPEN https://github.com/loft-sh/vcluster-docs/pull/1234' ]
}

@test "a Linear id still opens the Linear issue" {
  run "$SCRIPT" 'DEVOPS-1693'
  [ "$status" -eq 0 ]
  [ "$output" = 'OPEN https://linear.app/loft/issue/DEVOPS-1693' ]
}

@test "the ctrl+4 hint finds each ref on a cockpit PRS row" {
  regex="$(hint_regex)"
  [ -n "$regex" ]
  run grep -oE "$regex" <<<'PRS:     vcluster-docs#1234,Piotr1215/claude#9,repo#7,'
  [ "$status" -eq 0 ]
  [ "$output" = $'vcluster-docs#1234\nPiotr1215/claude#9\nrepo#7' ]
}

@test "the ctrl+4 hint is clickable with the mouse" {
  run awk '/^\[\[hints.enabled\]\]/ { block = "" } { block = block "\n" $0 }
    /^binding = \{ key = "4"/ { print block; exit }' "$ALACRITTY"
  [[ "$output" == *"mouse.enabled = true"* ]]
}
