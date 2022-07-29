# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Path to your oh-my-zsh installation.
export ZSH="${HOME}/.oh-my-zsh"

#ZSH_THEME="spaceship"
ZSH_THEME="simple" #Best theme ever
#ZSH_THEME="powerlevel10k/powerlevel10k"

# Add wisely, as too many plugins slow down shell startup.
if [[ $(uname -s) == Linux ]]; then
  plugins=(z git kubectl zsh-autosuggestions zsh-syntax-highlighting sudo web-search alias-finder colored-man-pages nix-shell)
else
  plugins=(z git kubectl zsh-autosuggestions zsh-syntax-highlighting sudo web-search alias-finder colored-man-pages)
fi
if [[ -z "$ZSH_CUSTOM" ]]; then
    ZSH_CUSTOM="$ZSH/custom"
fi
# don't run the completion function when being source-ed or eval-ed
if [ "$funcstack[1]" = "_k3d" ]; then
    _k3d
fi
# PROMPT CUSTOMIZATION
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
# [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Directory history
setopt AUTO_PUSHD                  # pushes the old directory onto the stack
setopt PUSHD_MINUS                 # exchange the meanings of '+' and '-'
setopt CDABLE_VARS                 # expand the expression (allows 'cd -2/tmp')
setopt auto_cd
setopt extended_glob
autoload -Uz compinit && compinit   # load + start completion
zstyle ':completion:*:directory-stack' list-colors '=(#b) #([0-9]#)*( *)==95=38;5;12'

source $ZSH/oh-my-zsh.sh
autoload -U compinit && compinit

if [[ $(uname -s) == Linux ]]; then
  source ${HOME}/.oh-my-zsh/custom/plugins/nix-shell/nix-shell.plugin.zsh
  source ${HOME}/.oh-my-zsh/custom/plugins/nix-zsh-completions/nix-zsh-completions.plugin.zsh
  fpath=(${HOME}/.oh-my-zsh/custom/plugins/nix-zsh-completions/nix-zsh-completions.plugin.zsh $fpath)
  prompt_nix_shell_setup
fi

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

alias tf=terraform
alias df=duf
alias ps=procs
alias ldoc='lazydocker'
alias wm='watch kubectl get managed'
alias rm='rm -i'
alias rmm='rm'
alias yx='y -t '
alias gs='git show'
alias y=z
alias op='xdg-open '
alias ddgit='web_search github'
alias lg='lazygit'
alias lvim='nvim -c "normal '\''0"'
alias redirect="2>&1 | tee output.txt"
alias go16="go1.16.15"
alias yml="cat <<EOF | kubectl create -f -"
alias mux=tmuxinator
alias ra=ranger
alias alaw='nohup alacritty --working-directory $PWD >&/dev/null'
alias ghs='gh s'
alias ls='exa --long --all --header --icons'
alias la='exa --long --grid --all --sort=accessed --reverse --header --icons'
if [[ $(uname -s) == Linux ]]; then
  alias cat=batcat
else
  alias cat=bat
fi
alias lzd='docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock -v /config/lazydocker:/.config/jesseduffield/lazydocker lazyteam/lazydocker'
alias rest='shutdown now'
alias nedit='vim -c "SLoad vim"'
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
alias dca='code ${HOME}/dev/dca-prep-kit'
alias lst='dpkg -l' #List installed packages with their description
alias dpsa="docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}'" #docker ps -a with only id name and image
alias gmail='web_search duckduckgo \!gmail'
alias disk='gdu'
alias mkdd='mkdir $(date +"%Y-%m-%d")'
alias admin='sudo bash -c "apt-get update && apt-get -y upgrade && apt-get -y autoremove && apt-get -y clean"'
alias sr='source ~/.zshrc'

if [[ $(uname -s) == Linux ]]; then
  eval $(dircolors -p | sed -e 's/DIR 01;34/DIR 01;36/' | dircolors /dev/stdin)
else
  export CLICOLOR=YES
  export LSCOLORS="Gxfxcxdxbxegedabagacad"
fi

# EXPORT & PATH
export PATH=/home/decoder/.nimble/bin:$PATH
export KUBECONFIG=~/.kube/config
export GOPATH=$HOME/go/
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
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# source ~/.github_variables

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# USER FUNCTIONS

function copyname() {
    file=$1
    stat -t $1 | cut -d '.' -f1 | xargs echo -n | xclip
}

function ytd() {
    link=$(xsel -ob)

    if [[ "$link" != *"youtu.be"* ]]; then
        echo "This is not the right format, copy again"
        return 1 2>/dev/null
    fi

    youtube-dl -o "~/music/%(title)s.%(ext)s"  $link --no-playlist &
}

function cpa() {
    printf $PWD | xclip -selection primary 
}

function dpa() {
    cd $(xclip -o -sel primary)
}

function gac() {
  git add .
  git commit -m "$1"
  git push
}

function gacs() {
  git add .
  git commit -m "$1" -s
  git push
}

# Find a repo for authenticated user with gh CLI and cd into it, clone and cd if not found on disk
function repo() {
    if [[ -z "$1" ]]; then
        echo "Please provide search term"
        return
    else
        export repo=$({ gh repo list Piotr1215 --limit 1000;  gh repo list upbound --limit 1000 } | awk '{print $1}' | sed 's:.*/::' | rg $1 | fzf)
    fi
    if [[ -z "$repo" ]]; then
        echo "Repository not found"
    elif [[ -d ${HOME}/dev/$repo ]]; then
        echo "Repository found locally, entering"
        cd ${HOME}/dev/$repo
        onefetch
    else
        echo "Repository not found locally, cloning"
        gh repo clone $repo ${HOME}/dev/$repo
        cd ${HOME}/dev/$repo
        onefetch
    fi
}

function checkfetch() {
    local res=$(onefetch) &> /dev/null
    if [[ "$res" =~ "Error" ]]; then
        echo ""
    else echo $(onefetch)
    fi
}

function key() {
  cat ${HOME}/scripts/shortcuts.txt |  yad --width=750 --height=1050  --center --close-on-unfocus --text-info
}

function kcdebug() {
  kubectl run -i --rm --tty debug --image=busybox --restart=Never -- sh
}

function mkd() {
  mkdir -p "$@" && cd "$_";
}

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

function iapt() {
    if [ -z "$1" ]; then
        echo "Usage: iapt <initial search string> - select packages on peco and they will be installed" 
    else 
        sudo apt-cache search $1 | peco | awk '{ print $1 }' | tr "\n" " " | xargs -- sudo apt-get -y install
    fi  
}

function pet-select() {
  BUFFER=$(pet search --query "$LBUFFER")
  CURSOR=$#BUFFER
  zle redisplay
}
zle -N pet-select
stty -ixon
bindkey '^s' pet-select
bindkey '^I' autosuggest-accept

[[ /usr/local/bin/kubectl ]] && source <(kubectl completion zsh)

# Prompt
source ${HOME}/kube-ps1/kube-ps1.sh
PROMPT='$(kube_ps1)'$PROMPT
PROMPT="$PROMPT"$'\n→ '

# Cloud Shells Settings
# source '${HOME}/lib/azure-cli/az.completion'

# The next line updates PATH for the Google Cloud SDK.
if [ -f '${HOME}/google-cloud-sdk/path.zsh.inc' ]; then . '${HOME}/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '${HOME}/google-cloud-sdk/completion.zsh.inc' ]; then . '${HOME}/google-cloud-sdk/completion.zsh.inc'; fi

eval "$(direnv hook zsh)"

### Added by Zinit's installer
if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
    print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
    command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
    command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" && \
        print -P "%F{33} %F{34}Installation successful.%f%b" || \
        print -P "%F{160} The clone has failed.%f%b"
fi

source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# Load a few important annexes, without Turbo
# (this is currently required for annexes)
zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust

### End of Zinit's installer chunk
