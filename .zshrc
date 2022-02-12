# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="/home/decoder/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
#ZSH_THEME="spaceship"
ZSH_THEME="simple"
#ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in ~/.oh-my-zsh/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to automatically update without prompting.
# DISABLE_UPDATE_PROMPT="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS=true

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="false"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in ~/.oh-my-zsh/plugins/*
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git kubectl zsh-autosuggestions zsh-syntax-highlighting sudo web-search)

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi


# PROMPT CUSTOMIZATION
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
# [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh


source $ZSH/oh-my-zsh.sh

alias ghs='gh s'
alias ls='exa --long --all --header --icons'
alias la='exa --long --grid --all --sort=modified --header --icons'
alias cat=batcat
alias lzd='docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock -v /config/lazydocker:/.config/jesseduffield/lazydocker lazyteam/lazydocker'
alias die='shutdown now'
alias vedit='vim ~/.config/nvim/init.vim'
alias zedit='vim ~/.zshrc'
alias vim='nvim'
alias gcc='git diff --stat --cached origin/master' # Git Check Commit before pushing
alias docs='docsify serve docs'
alias glog='git log --graph --oneline --decorate'
alias music='browse https://www.youtube.com/playlist?list=PL3-_0fT8ay_I9cEIoPNKRN7PcGjnAZ1Re'
alias getupd='source ${HOME}/scripts/getupdates.sh'
alias k=kubectl
alias dev='cd ~/dev'
alias kdump='kubectl get all --all-namespaces'
alias addkey='eval $(ssh-agent) && ssh-add'
alias ll='ls -lah'
alias l='lsd -al'
alias lol=lolcat
alias lal='lsd -al | lolcat -a -d 5'
alias km=kustomize
alias vz='vim ~/.zshrc'
alias diskusage='du -sh * | sort -h --reverse'
alias cls=clear
alias dls="docker container ls -a"
alias serve="browser-sync start -s -f . --no-notify --host localhost --port 5000"
alias dca='code /home/decoder/dev/dca-prep-kit'
alias lst='dpkg -l' #List installed packages with their description
alias dpsa="docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}'" #docker ps -a with only id name and image
alias gmail='web_search duckduckgo \!gmail'
alias disk='gdu'
alias mkdd='mkdir $(date +"%Y-%m-%d")'
alias admin='sudo bash -c "apt-get update && apt-get -y upgrade && apt-get -y autoremove && apt-get -y clean"'
alias sr='source ~/.zshrc'

eval $(dircolors -p | sed -e 's/DIR 01;34/DIR 01;36/' | dircolors /dev/stdin)

# EXPORT & PATH
export KUBECONFIG=~/.kube/config
export KUBECONFIG=~/.kube/config:~/.kube/config-vagrant
export PATH=$PATH:$HOME/.krew/bin
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
export PATH=$HOME/.local/bin:$PATH
export PATH=$HOME/scripts:$PATH
export PATH=$HOME/go/bin:$PATH
export FONTCONFIG_PATH=/etc/fonts
export EDITOR=nvim
export GOPATH=$HOME/go/
export GH_USER=Piotr1215
export STARSHIP_CONFIG=/home/decoder/.config/starship.toml

source ~/.github_variables

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# USER FUNCTIONS

function gac() {
  git add .
  git commit -m "$1"
  git push
}

function key() {
  cat /home/decoder/scripts/shortcuts.txt |  yad --width=750 --height=750  --center --close-on-unfocus --text-info
}

function kcdebug() {
  kubectl run -i --rm --tty debug --image=busybox --restart=Never -- sh
}

function mkd() {
  mkdir -p "$@" && cd "$_";
}

function pex() {

    pet exec -q = $@;
}

function prev() {
  PREV=$(fc -lrn | head -n 1)
  sh -c "pet new `printf %q "$PREV"`"
}

function iapt() {
    if [ -z "$1" ]; then
        echo "Usage: iapt <initial search string> - select packages on peco and they will be installed" 
    else 
        sudo apt-cache search $1 | peco | awk '{ print $1 }' | tr "\n" " " | xargs -- sudo apt-get -y install
    fi  
}

function peco-directories() {
  local current_lbuffer="$LBUFFER"
  local current_rbuffer="$RBUFFER"
  if command -v fd >/dev/null 2>&1; then
    local dir="$(command fd --type directory --hidden --no-ignore --exclude .git/ --color never 2>/dev/null | peco )"
  else
    local dir="$(
      command find \( -path '*/\.*' -o -fstype dev -o -fstype proc \) -type d -print 2>/dev/null \
      | sed 1d \
      | cut -b3- \
      | awk '{a[length($0)" "NR]=$0}END{PROCINFO["sorted_in"]="@ind_num_asc"; for(i in a) print a[i]}' - \
      | peco
    )"
  fi

  if [ -n "$dir" ]; then
    dir=$(echo "$dir" | tr --delete '\n')
    dir=$(printf %q "$dir")

    BUFFER="${current_lbuffer}${file}${current_rbuffer}"
    CURSOR=$#BUFFER
  fi
}

function iopen {
  local current_lbuffer="$LBUFFER"
  local current_rbuffer="$RBUFFER"
  if command -v fd >/dev/null 2>&1; then
    local file="$(command fd --type file --hidden --no-ignore --exclude .git/ --color never 2>/dev/null | peco)"
  elif command -v rg >/dev/null 2>&1; then
    local file="$(rg --glob "" --files --hidden --no-ignore-vcs --iglob !.git/ --color never 2>/dev/null | peco)"
  elif command -v ag >/dev/null 2>&1; then
    local file="$(ag --files-with-matches --unrestricted --skip-vcs-ignores --ignore .git/ --nocolor -g "" 2>/dev/null | peco)"
  else
    local file="$(
    command find \( -path '*/\.*' -o -fstype dev -o -fstype proc \) -type f -print 2> /dev/null \
      | sed 1d \
      | cut -b3- \
      | awk '{a[length($0)" "NR]=$0}END{PROCINFO["sorted_in"]="@ind_num_asc"; for(i in a) print a[i]}' - \
      | peco
    )"
  fi

  if [ -n "$file" ]; then
    file=$(echo "$file" | tr --delete '\n')
    file=$(printf %q "$file")
    BUFFER="${current_lbuffer}${file}${current_rbuffer}"
    CURSOR=$#BUFFER
  fi
}

zle -N peco-directories
bindkey '^Xf' peco-directories
zle -N peco-files
bindkey '^X^f' peco-files


[[ /usr/local/bin/kubectl ]] && source <(kubectl completion zsh)

export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

source /home/decoder/kube-ps1/kube-ps1.sh
PROMPT='$(kube_ps1)'$PROMPT
PROMPT="$PROMPT"$'\n→ '

#eval "$(starship init zsh)"
