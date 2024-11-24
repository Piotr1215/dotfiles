# Add deno completions to search path
if [[ ":$FPATH:" != *":/home/decoder/.zsh/completions:"* ]]; then export FPATH="/home/decoder/.zsh/completions:$FPATH"; fi
# zmodload zsh/zprof
# Path to your oh-my-zsh installation.
export ZSH="${HOME}/.oh-my-zsh"

if [[ -z $TMUX ]]; then
  tmuxinator start poke
fi

ZSH_THEME="simple" #Best theme ever
ZVM_INIT_MODE=sourcing
autoload -Uz compinit
compinit -d "${ZDOTDIR:-$HOME}/.zcompdump"

# https://github.com/jeffreytse/zsh-vi-mode
function zvm_config() {
  ZVM_LINE_INIT_MODE=$ZVM_MODE_INSERT
  ZVM_VI_INSERT_ESCAPE_BINDKEY=\;\;
  ZVM_CURSOR_STYLE_ENABLED=false
  ZVM_VI_EDITOR=nvim
# export KEYTIMEOUT=1
}

function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}

function zvm_after_init() {
  zvm_bindkey viins '^Q' push-line
}

# PUGINS & MODULES
# fzf-tab should be last because it binds to ^I
plugins=(z git kubectl zsh-autosuggestions zsh-syntax-highlighting web-search colored-man-pages fzf-tab sudo)
zmodload zsh/mapfile # Bring mapfile functionality similar to bash

# The plugin will auto execute this zvm_after_lazy_keybindings function
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
zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup
# disable sort when completing `git checkout`
zstyle ':completion:*:git-checkout:*' sort false
# set descriptions format to enable group support
# NOTE: don't use escape sequences here, fzf-tab will ignore them
zstyle ':completion:*:descriptions' format '[%d]'
# set list-colors to enable filename colorizing
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
# force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
zstyle ':completion:*' menu no
# preview directory's content with exa when completing cd
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'exa -1 --color=always $realpath'
# switch group using `<` and `>`
zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:*' popup-min-size 75 20

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

# Completions and scripts
source $ZSH/oh-my-zsh.sh
source ~/.oh-my-zsh/plugins/tmuxinator/_mst 
source ~/.oh-my-zsh/plugins/tmuxinator/_ms
source ~/.oh-my-zsh/plugins/tmuxinator/_fifp
source ~/scripts/__gh_cli.sh

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
source ~/.zsh_abbreviations

# EXPORT & PATH
export XDG_CONFIG_HOME=~/.config
export XDG_CONFIG_DIRS=/home/decoder/dev/dotfiles/.config/nvim:$XDG_CONFIG_DIRS
export FZF_BASE=/usr/bin/fzf
export FZF_DEFAULT_COMMAND='fd --hidden --exclude .git'
export FZF_CTRL_T_COMMAND='fd --hidden'
export FZF_ALT_C_COMMAND='fd --hidden'
export VISUAL=nvim
export PATH=/home/decoder/.nimble/bin:$PATH
export KUBECONFIG=~/.kube/config
export GOPATH=/usr/local/go
export GOBIN=/usr/local/go/bin
export PATH="/usr/bin:/home/decoder/.local/bin:$PATH"
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
export RIPGREP_CONFIG_PATH=$HOME/.ripgreprc
export COLLECT_LEARNINGS_OPT_OUT=true  # Opt out of collecting learning data
export CLIPBOARD_NOGUI=0  # Enable GUI-based clipboard operations
export WEATHER_LOCATION=Mittelbuchen

if [ -d "$HOME/.dotnet/tools" ] ; then
    PATH="$HOME/.dotnet/tools:$PATH"
fi

# source ~/.github_variables

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
zvm_after_init_commands+=('[ -f ~/.fzf ] && source ~/.fzf')

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

function open_fabric() {
  alacritty --working-directory "$(pwd)" -e zsh -c '
    __orchestrator.sh
  '
}

# Binds Ctrl+Alt+A to open_fabric
bindkey "^X^A" open_fabric                # Ctrl+X Ctrl+A: Opens fabric script
zle -N open_fabric

function open_file_git_staged() {
   __open-file-git-staged.sh 
}

# Binds Ctrl+Alt+O to open_file_git
bindkey "^[^O" open_file_git_staged       # Ctrl+Alt+O: Opens file in git staged
zle -N open_file_git_staged

# Unified function definition
function output_file_path() {
    local search_dir="$1"
    
    # Use fd or find to list files and pipe into fzf for selection
    local selected_file=$(fd . "$search_dir" | fzf)

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

source /home/decoder/dev/dotfiles/scripts/__grep_and_open.sh
bindkey -s '^[q' 'gif\n'                  # Alt+q: Inserts 'gif' and a newline


# Wrapper functions for key bindings
function output_file_path_current() {
    output_file_path "."
}

function output_file_path_home() {
    output_file_path "$HOME"
}

zle -N output_file_path_current
zle -N output_file_path_home
bindkey '^[f' output_file_path_current # Alt+f: Outputs current file path
bindkey '^[F' output_file_path_home # Alt+Shift+F: Outputs home file path

function toggle_window_pinned() {
 ~/dev/dotfiles/scripts/__toggle_keep_top.sh 
}
zle -N toggle_window_pinned
bindkey '^[w' toggle_window_pinned        # Alt+w: Toggles window pinned state

function pet-select() {
  RBUFFER=$(pet search)
  if [[ "$RBUFFER" =~ ^"xdg-open" ]]; then
    eval "$RBUFFER" >/dev/null 2>&1 &
    zle send-break  # This will exit the current command line
  else
    CURSOR=$#BUFFER
    zle redisplay
  fi
}

zle -N pet-select
stty -ixon
bindkey '^s' pet-select  # Ctrl+s: Selects pet snippet

function zoxider() {
  BUFFER=$(zoxide query -i)
  zle accept-line
}

zle -N zoxider
bindkey '^[j' zoxider                     # Alt+j: Executes zoxider command

function f_enter() {
  BUFFER="__open-file.sh"
  zle accept-line
}

zle -N f_enter
bindkey '^f' f_enter                      # Ctrl+f: Enters f mode

# PROJECT: git-log
# function open_logg() {
  # BUFFER="logg"
  # zle accept-line
# }

function paste_file_content() {
    LBUFFER="xclip -o -sel clipboard > "
    zle reset-prompt
}
zle -N paste_file_content
bindkey '^X^P' paste_file_content

function copy_file_content() {
  local selected_file
  selected_file=$(fd --type f | fzf --height 40% --reverse)
  if [[ -n "$selected_file" ]]; then
      xclip -selection clipboard -in "$selected_file"
  else
    zle -M "No file selected."
  fi
  zle reset-prompt
  zle redisplay
}

zle -N copy_file_content
bindkey '^X^F' copy_file_content     

# zle -N open_logg
# bindkey '^l' open_logg

function f_git_enter() {
  BUFFER="__open-file-git.sh"
  zle accept-line
}

zle -N f_git_enter
bindkey '^o' f_git_enter                      # Ctrl+o: Enters git mode
copy-line-to-clipboard() {
  echo -n $BUFFER | xclip -selection clipboard
}
zle -N copy-line-to-clipboard
bindkey '^Y' copy-line-to-clipboard       # Ctrl+Y: Copies line to clipboard
bindkey '^@' autosuggest-accept           # Ctrl+@: Accepts autosuggestion
bindkey '^X^T' transpose-words            # Ctrl+X Ctrl+T: Transposes words

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
eval "$(thefuck --alias)"
# bun completions
[ -s "/home/decoder/.oh-my-zsh/completions/_bun" ] && source "/home/decoder/.oh-my-zsh/completions/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export WASMTIME_HOME="$HOME/.wasmtime"

export PATH="$WASMTIME_HOME/bin:$PATH"
if [ -f "/home/decoder/.config/fabric/fabric-bootstrap.inc" ]; then . "/home/decoder/.config/fabric/fabric-bootstrap.inc"; fi
# zprof > /tmp/zprof.out
. "/home/decoder/.deno/env"
