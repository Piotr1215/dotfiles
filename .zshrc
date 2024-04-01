# zmodload zsh/zprof
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

autoload -Uz compinit
compinit -d "${ZDOTDIR:-$HOME}/.zcompdump"

# PUGINS 
plugins=(z git kubectl zsh-autosuggestions zsh-syntax-highlighting sudo web-search colored-man-pages)

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
setopt extended_glob
zstyle ':completion:*:directory-stack' list-colors '=(#b) #([0-9]#)*( *)==95=38;5;12'

# Turn history on to have cd - history
SAVEHIST=1000
HISTSIZE=1000

setopt append_history           # append
setopt hist_ignore_all_dups     # no duplicate
unsetopt hist_ignore_space      # ignore space prefixed commands
setopt hist_reduce_blanks       # trim blanks
setopt hist_verify              # show before executing history commands
setopt inc_append_history       # add commands as they are typed, don't wait until shell exit 
setopt share_history            # share hist between sessions
setopt bang_hist                # !keyword
HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history

# Gnome related Settings
# Enable animations
gsettings set org.gnome.desktop.interface enable-animations true

source $ZSH/oh-my-zsh.sh
source ~/.oh-my-zsh/plugins/tmuxinator/_mst 
source ~/.oh-my-zsh/plugins/tmuxinator/_ms

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

# EXPORT & PATH
export XDG_CONFIG_HOME=~/.config
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
export PATH=$PATH:$HOME/.local/bin
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

function open_file_git_staged() {
   __open-file-git-staged.sh 
}

# Binds Ctrl+Alt+O to open_file_git
bindkey "^[^O" open_file_git_staged
zle -N open_file_git_staged

function pet-select-bmk() {
  BUFFER=$(pet search --tag link)
  zle redisplay
}

zle -N pet-select-bmk
bindkey '^t' pet-select-bmk

function output_file_path() {
    # Use fd or find to list files and pipe into fzf for selection
    local selected_file=$(fd . | fzf)

    # Check if a file was selected
    if [[ -n $selected_file ]]; then
        # Convert to absolute path (realpath can also be used)
        local absolute_path=$(realpath "$selected_file")

        # Append the selected file's path to the current command line
        BUFFER="$BUFFER $absolute_path"
        CURSOR=$#BUFFER  # Move cursor to the end of the line
    fi

    zle reset-prompt  # Redraw the prompt to reflect the updated BUFFER
    zle .redisplay  # Explicitly request a redisplay
}

zle -N output_file_path
bindkey '^[f' output_file_path

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
bindkey '^X^T' transpose-words

stty -ixon

[[ /usr/local/bin/kubectl ]] && source <(kubectl completion zsh)
[[ /usr/local/bin/kubecolor ]] && source <(kubecolor completion zsh)

# Prompt
source ${HOME}/kube-ps1/kube-ps1.sh
PROMPT='$(kube_ps1)'$PROMPT
PROMPT="$PROMPT"$'\n→ '

[[ -s "/home/decoder/.gvm/scripts/gvm" ]] && source "/home/decoder/.gvm/scripts/gvm"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/decoder/dev/clusters/primary-dev/google-cloud-sdk/path.zsh.inc' ]; then . '/home/decoder/dev/clusters/primary-dev/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/decoder/dev/clusters/primary-dev/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/decoder/dev/clusters/primary-dev/google-cloud-sdk/completion.zsh.inc'; fi

eval "$(direnv hook zsh)"
eval "$(starship init zsh)"
# zprof > /tmp/zprof.out

# bun completions
[ -s "/home/decoder/.oh-my-zsh/completions/_bun" ] && source "/home/decoder/.oh-my-zsh/completions/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
