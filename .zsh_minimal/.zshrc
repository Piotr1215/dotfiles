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
# Prompt
source ${HOME}/kube-ps1/kube-ps1.sh
PROMPT='$(kube_ps1)'$PROMPT
PROMPT="$PROMPT"$'\n→ '
export CLICOLOR=YES
export LSCOLORS="Gxfxcxdxbxegedabagacad"
# This prevents the 'too many files error' when running PackerSync
ulimit -n 10240
