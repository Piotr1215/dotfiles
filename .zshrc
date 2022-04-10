# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Path to your oh-my-zsh installation.
export ZSH="/home/decoder/.oh-my-zsh"

#ZSH_THEME="spaceship"
ZSH_THEME="simple"
#ZSH_THEME="powerlevel10k/powerlevel10k"

# Add wisely, as too many plugins slow down shell startup.
plugins=(git kubectl zsh-autosuggestions zsh-syntax-highlighting sudo web-search alias-finder colored-man-pages nix-shell)

# PROMPT CUSTOMIZATION
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
# [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Directory history
setopt AUTO_PUSHD                  # pushes the old directory onto the stack
setopt PUSHD_MINUS                 # exchange the meanings of '+' and '-'
setopt CDABLE_VARS                 # expand the expression (allows 'cd -2/tmp')
autoload -U compinit && compinit   # load + start completion
zstyle ':completion:*:directory-stack' list-colors '=(#b) #([0-9]#)*( *)==95=38;5;12'

source $ZSH/oh-my-zsh.sh
source /home/decoder/.oh-my-zsh/custom/plugins/nix-shell/nix-shell.plugin.zsh


alias lvim='nvim -c "normal '\''0"'
alias redirect="2>&1 | tee output.txt"
alias go16="go1.16.15"
alias yml="cat <<EOF | kubectl create -f -"
alias mux=tmuxinator
alias ra=ranger
alias alaw='nohup alacritty --working-directory $PWD >&/dev/null'
alias ghs='gh s'
alias ls='exa --long --all --header --icons'
alias la='exa --long --grid --all --sort=modified --header --icons'
alias cat=batcat
alias lzd='docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock -v /config/lazydocker:/.config/jesseduffield/lazydocker lazyteam/lazydocker'
alias rest='shutdown now'
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
export PATH=$PATH:$HOME/.krew/bin
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
export PATH=$HOME/.local/bin:$PATH
export PATH=$HOME/scripts:$PATH
export PATH=$HOME/go/bin:$PATH
export PATH=$PATH:/usr/local/go/bin
export PATH=$PATH:$HOME/.istioctl/bin
export FONTCONFIG_PATH=/etc/fonts
export EDITOR=nvim
export GOPATH=$HOME/go/
export GH_USER=Piotr1215
export STARSHIP_CONFIG=/home/decoder/.config/starship.toml
export PLANTUML_LIMIT_SIZE=8192
export DEMODIR=/home/decoder/dev/crossplane-scenarios
export git_main_branch=main
export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
export PATH=$PATH:/home/decoder/bin
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# source ~/.github_variables

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# USER FUNCTIONS

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
    elif [[ -d /home/decoder/dev/$repo ]]; then
        echo "Repository found locally, entering"
        cd /home/decoder/dev/$repo
        onefetch
    else
        echo "Repository not found locally, cloning"
        gh repo clone $repo /home/decoder/dev/$repo
        cd /home/decoder/dev/$repo
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
  cat /home/decoder/scripts/shortcuts.txt |  yad --width=750 --height=1050  --center --close-on-unfocus --text-info
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

[[ /usr/local/bin/kubectl ]] && source <(kubectl completion zsh)

# Prompt
source /home/decoder/kube-ps1/kube-ps1.sh
PROMPT='$(kube_ps1)'$PROMPT
PROMPT="$PROMPT"$'\n→ '

# Cloud Shells Settings
source '/home/decoder/lib/azure-cli/az.completion'

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/decoder/google-cloud-sdk/path.zsh.inc' ]; then . '/home/decoder/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/decoder/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/decoder/google-cloud-sdk/completion.zsh.inc'; fi

eval "$(direnv hook zsh)"
