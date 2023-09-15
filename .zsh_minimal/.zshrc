# Load aliases and functions
source ~/.zsh_aliases
source ~/.zsh_functions

ZSH_THEME="simple" #Best theme ever

# Initialize direnv
eval "$(direnv hook zsh)"

# Enable basic syntax highlighting
autoload -Uz colors && colors

# Enable tab completion
autoload -Uz compinit && compinit

fpath=(${HOME}/.oh-my-zsh/completions/ $fpath)
# Set ZSH_CUSTOM dir if env var not present
if [[ -z "$ZSH_CUSTOM" ]]; then
    ZSH_CUSTOM="$ZSH/custom"
fi
export CLICOLOR=YES
export LSCOLORS="Gxfxcxdxbxegedabagacad"
# This prevents the 'too many files error' when running PackerSync
ulimit -n 10240
parse_git_dirty() {
  git_status="$(git status 2> /dev/null)"
  [[ "$git_status" =~ "Changes to be committed:" ]] && echo -n "%F{green}·%f"
  [[ "$git_status" =~ "Changes not staged for commit:" ]] && echo -n "%F{yellow}·%f"
  [[ "$git_status" =~ "Untracked files:" ]] && echo -n "%F{red}·%f"
}

setopt prompt_subst

NEWLINE=$'\n'

autoload -Uz vcs_info # enable vcs_info
precmd () { vcs_info } # always load before displaying the prompt
zstyle ':vcs_info:git*' formats ' ⇒ (%F{254}%b%F{245})' # format $vcs_info_msg_0_

PS1='%F{245}%F{153}%(5~|%-1~/⋯/%3~|%4~)%F{245}${vcs_info_msg_0_} $(parse_git_dirty)$NEWLINE%F{254}$%f '

