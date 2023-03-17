# Path to your oh-my-zsh installation.
export ZSH="${HOME}/.oh-my-zsh"

# This sets vim key bindings mode.
# set -o vi

if [[ -z $TMUX ]]; then
  tmuxinator start poke
fi

#ZSH_THEME="spaceship"
#ZSH_THEME="powerlevel10k/powerlevel10k"
ZSH_THEME="simple" #Best theme ever

# PUGINS 
if [[ $(uname -s) == Linux ]]; then
  plugins=(z git kubectl zsh-autosuggestions zsh-syntax-highlighting sudo web-search alias-finder colored-man-pages nix-shell)
else
  plugins=(z git kubectl zsh-autosuggestions zsh-syntax-highlighting sudo web-search alias-finder colored-man-pages)
fi

# Set ZSH_CUSTOM dir if env var not present
if [[ -z "$ZSH_CUSTOM" ]]; then
    ZSH_CUSTOM="$ZSH/custom"
fi

# Don't run the completion function when being source-ed or eval-ed
if [ "$funcstack[1]" = "_k3d" ]; then
    _k3d
fi

eval "$(zoxide init zsh)"

# Directory history
setopt AUTO_PUSHD                  # pushes the old directory onto the stack
setopt PUSHD_MINUS                 # exchange the meanings of '+' and '-'
setopt CDABLE_VARS                 # expand the expression (allows 'cd -2/tmp')
setopt auto_cd
setopt extended_glob
zstyle ':completion:*:directory-stack' list-colors '=(#b) #([0-9]#)*( *)==95=38;5;12'

# Turn history on to have cd - history
SAVEHIST=10000
HISTSIZE=5000

setopt append_history           # append
setopt hist_ignore_all_dups     # no duplicate
unsetopt hist_ignore_space      # ignore space prefixed commands
setopt hist_reduce_blanks       # trim blanks
setopt hist_verify              # show before executing history commands
setopt inc_append_history       # add commands as they are typed, don't wait until shell exit 
setopt share_history            # share hist between sessions
setopt bang_hist                # !keyword
HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history

source $ZSH/oh-my-zsh.sh
autoload -U compinit && compinit

# Add nix shell to prompt if in nix env
if [[ $(uname -s) == Linux ]]; then
  source ${HOME}/.oh-my-zsh/custom/plugins/nix-shell/nix-shell.plugin.zsh
  source ${HOME}/.oh-my-zsh/custom/plugins/nix-zsh-completions/nix-zsh-completions.plugin.zsh
  fpath=(${HOME}/.oh-my-zsh/custom/plugins/nix-zsh-completions/nix-zsh-completions.plugin.zsh $fpath)
  prompt_nix_shell_setup
fi

if [[ $(uname -s) == Linux ]]; then
  eval $(dircolors -p | sed -e 's/DIR 01;34/DIR 01;36/' | dircolors /dev/stdin)
else
  export CLICOLOR=YES
  export LSCOLORS="Gxfxcxdxbxegedabagacad"
fi

# Source functions and aliases
source ~/.zsh_aliases
source ~/.zsh_functions
eval "$(direnv hook zsh)"

# EXPORT & PATH
export FZF_DEFAULT_COMMAND='fd --hidden'
export FZF_CTRL_T_COMMAND='fd --hidden'
export VISUAL=nvim
export PATH=/home/decoder/.nimble/bin:$PATH
export KUBECONFIG=~/.kube/config
export GOPATH=/usr/local/go
export GOBIN=/usr/local/go/bin
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$HOME/.krew/bin
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
export PATH=$HOME/.local/bin:$PATH
export PATH=$HOME/scripts:$PATH
export PATH=$HOME/go/bin:$PATH
export PATH=$HOME/go:$PATH
export PATH=$PATH:/usr/local/go/bin
export PATH=$PATH:$HOME/.istioctl/bin
export FONTCONFIG_PATH=/etc/fonts
export EDITOR=nvim
export GH_USER=Piotr1215
export STARSHIP_CONFIG=${HOME}/.config/starship.toml
export PLANTUML_LIMIT_SIZE=8192
export DEMODIR=${HOME}/dev/crossplane-scenarios
export git_main_branch=main
export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
export PATH=$PATH:${HOME}/bin
export NVM_DIR="$HOME/.nvm"
export RANGER_LOAD_DEFAULT_RC=FALSE
export RIPGREP_CONFIG_PATH=$HOME/.ripgreprc
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# source ~/.github_variables

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

function pex() {
    pet exec
}

function psx() {
    pet exec -q $1
}
function prev() {
  PREV=$(fc -lrn | head -n 1)
  sh -c "pet new `printf %q "$PREV"`"
}

function pet-select() {
  BUFFER=$(pet search --query "$LBUFFER")
  CURSOR=$#BUFFER
  zle redisplay
}

zle -N pet-select
stty -ixon
bindkey '^s' pet-select
bindkey '^@' autosuggest-accept

[[ /usr/local/bin/kubectl ]] && source <(kubectl completion zsh)
[[ /usr/local/bin/kubecolor ]] && source <(kubecolor completion zsh)

# Prompt
source ${HOME}/kube-ps1/kube-ps1.sh
PROMPT='$(kube_ps1)'$PROMPT
PROMPT="$PROMPT"$'\n→ '

# Cloud Shells Settings
# source '${HOME}/lib/azure-cli/az.completion'

[[ -s "/home/decoder/.gvm/scripts/gvm" ]] && source "/home/decoder/.gvm/scripts/gvm"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/decoder/dev/clusters/primary-dev/google-cloud-sdk/path.zsh.inc' ]; then . '/home/decoder/dev/clusters/primary-dev/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/decoder/dev/clusters/primary-dev/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/decoder/dev/clusters/primary-dev/google-cloud-sdk/completion.zsh.inc'; fi

eval "$(starship init zsh)"

