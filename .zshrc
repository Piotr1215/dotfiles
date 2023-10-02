# zmodload zsh/zprof
# Path to your oh-my-zsh installation.
export ZSH="${HOME}/.oh-my-zsh"

# This sets vim key bindings mode.
# set -o vi

if [[ -z $TMUX ]]; then
  tmuxinator start poke
fi

# Initialize script usage tracking file
if [ ! -f "/home/decoder/dev/dotfiles/.script_usage.json" ]; then
  echo '{}' > /home/decoder/dev/dotfiles/.script_usage.json
fi

# Load aliases into a variable from the specific file
alias_list=$(awk -F'[ =]' '/^alias / {print $2}' /home/decoder/.zsh_aliases)

# Zsh preexec function
preexec() {
  # echo "Debug: preexec called with $1"  # Debug line
  local cmd=$(echo $1 | awk '{print $1}' | sed 's/^.\///')
  local folder=$(pwd)
  local json_file="/home/decoder/dev/dotfiles/.script_usage.json"

  # echo "Debug: cmd=$cmd, functions=\${functions[$cmd]}, alias_list= $alias_list "  # Debug line
  # Check if the command is a script in the specific folder or a defined function
  if [[ -f "/home/decoder/dev/dotfiles/scripts/$cmd" || -n "${functions[$cmd]}" || " $alias_list " == *"$cmd"* ]]; then
    # echo "Debug: Inside if condition"  # Debug line
    # Update JSON file
    jq --arg cmd "$cmd" --arg folder "$folder" '
      if has($cmd) then
        .[$cmd] += 1
      else
        .[$cmd] = 1
      end
    ' $json_file > tmp.json && mv tmp.json $json_file
  fi
}

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
setopt AUTO_CD                    # change to a directory without cd
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
source ~/.oh-my-zsh/plugins/tmuxinator/_mst 
source ~/.oh-my-zsh/plugins/tmuxinator/_msm
autoload -U compinit && compinit

# Add nix shell to prompt if in nix env
if [[ $(uname -s) == Linux ]]; then
  source ${HOME}/.oh-my-zsh/custom/plugins/nix-shell/nix-shell.plugin.zsh
  source ${HOME}/.oh-my-zsh/custom/plugins/nix-zsh-completions/nix-zsh-completions.plugin.zsh
  fpath=(${HOME}/.oh-my-zsh/custom/plugins/nix-zsh-completions/nix-zsh-completions.plugin.zsh $fpath)
  prompt_nix_shell_setup
fi

  fpath=(${HOME}/.oh-my-zsh/completions/ $fpath)

if [[ $(uname -s) == Linux ]]; then
  eval $(dircolors -p | sed -e 's/DIR 01;34/DIR 01;36/' | dircolors /dev/stdin)
else
  export CLICOLOR=YES
  export LSCOLORS="Gxfxcxdxbxegedabagacad"
  export TERM=alacritty
  # This prevents the 'too many files error' when running PackerSync
  ulimit -n 10240

fi

# Source functions and aliases
source ~/.zsh_aliases
source ~/.zsh_functions
eval "$(direnv hook zsh)"

# EXPORT & PATH
export FZF_BASE=/usr/bin/fzf
export FZF_DEFAULT_COMMAND='fd --hidden --exclude .git'
export FZF_CTRL_T_COMMAND='fd --hidden'
export FZF_ALT_C_COMMAND='fd --hidden'
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
export PATH=$PATH:$HOME/dev/dotfiles/scripts
export PATH=$PATH:$HOME/.luarocks/bin
export FONTCONFIG_PATH=/etc/fonts
export EDITOR=nvim
export GH_USER=Piotr1215
export STARSHIP_CONFIG=${HOME}/.config/starship.toml
export PLANTUML_LIMIT_SIZE=8192
export DEMODIR=${HOME}/dev/crossplane-scenarios
export git_main_branch=main
export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
export PATH=$PATH:${HOME}/bin
export RANGER_LOAD_DEFAULT_RC=FALSE
export RIPGREP_CONFIG_PATH=$HOME/.ripgreprc
# export NVM_DIR="$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
# autoload -U add-zsh-hook

# load-nvmrc() {
  # if [[ -f .nvmrc && -r .nvmrc ]]; then
    # nvm use
  # elif [[ $(nvm version) != $(nvm version default)  ]]; then
    # echo "Reverting to nvm default version"
    # nvm use default
  # fi
# }
# add-zsh-hook chpwd load-nvmrc
# load-nvmrc

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

function pet-select-bmk() {
  BUFFER=$(pet search --tag link)
  zle redisplay
}

zle -N pet-select-bmk
bindkey '^t' pet-select-bmk

function pet-select() {
  BUFFER=$(pet search --query "$LBUFFER")
  CURSOR=$#BUFFER
  zle redisplay
}

zle -N pet-select
bindkey '^s' pet-select

function zoxider() {
  BUFFER=$(zoxide query -i)
  zle accept-line
}

zle -N zoxider
bindkey '^j' zoxider

# function sessionizer_enter() {
  # BUFFER="__sessionizer.sh"
  # zle accept-line
# }

# zle -N sessionizer_enter
# bindkey '^x' sessionizer_enter

function f_enter() {
  BUFFER="__open-file.sh"
  zle accept-line
}

zle -N f_enter
bindkey '^f' f_enter

function f_git_enter() {
  BUFFER="__open-file-git.sh"
  zle accept-line
}

zle -N f_git_enter
bindkey '^o' f_git_enter
copy-line-to-clipboard() {
  echo -n $BUFFER | xclip -selection clipboard
}
zle -N copy-line-to-clipboard
bindkey '^Y' copy-line-to-clipboard
bindkey '^@' autosuggest-accept

stty -ixon

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
# zprof
