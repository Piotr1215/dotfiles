skip_global_compinit=1

# Editor lives here, not .zshrc: .zshrc is interactive-only, so anything spawned
# from a non-interactive zsh (scripts, detached tmux panes) inherited no $EDITOR
# and fell back to /usr/bin/vi -> vim.tiny. Claude Code's ctrl+g resolves
# $VISUAL -> $EDITOR -> first of code/vi/nano, and spawns the binary directly,
# so the `vim=nvim` alias never applies.
export EDITOR=nvim
export VISUAL=nvim

# classif: keep the model loaded until `classif pause` unloads it. A call that
# finds it unloaded pays a 3 to 5 s cold load; every call must stay under 1 s.
export CLASSIF_KEEP_ALIVE=-1

if [ -e /home/decoder/.nix-profile/etc/profile.d/nix.sh ]; then . /home/decoder/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer
. "$HOME/.cargo/env"
