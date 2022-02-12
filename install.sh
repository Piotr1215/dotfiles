#!/usr/bin/env bash

set -eo pipefail
IFS=$'\n\t'

# Define a function which rename a `target` file to `target.backup` if the file
# exists and if it's a 'real' file, ie not a symlink
backup() {
  target=$1
  if [ -e "$target" ]; then
    if [ ! -L "$target" ]; then
      mv "$target" "$target.backup"
      echo "-----> Moved your old $target config file to $target.backup"
    fi
  fi
}

symlink() {
  file=$1
  link=$2
  if [ ! -e "$link" ]; then
    echo "-----> Symlinking your new $link"
    ln -s $file $link
  fi
}

# For all files `$name` in the present folder except `*.sh`, `README.md`, `settings.json`,
# and `config`, backup the target file located at `~/.$name` and symlink `$name` to `~/.$name`
for name in *; do
  if [ ! -d "$name" ]; then
    target="$HOME/.$name"
    if [[ ! "$name" =~ '\.sh$' ]] && [ "$name" != 'README.md' ] && [[ "$name" != 'settings.json' ]] && [[ "$name" != 'config' ]]; then
      backup $target
      symlink $PWD/$name $target
    fi
  fi
done

# Set variables
NAME=$1
EMAIL=$2
GPG_KEY=$3

LOG="${HOME}/dotfiles.log"

process() {
  echo "$(date) PROCESSING:  $@" >> $LOG
  printf "$(tput setaf 6) [STEP ${STEP:-0}] %s...$(tput sgr0)\n" "$@"
  STEP=$((STEP+1))
}

if [ -z "$NAME" ]
then
  read -p "Please enter your git user.name, (for example, piotr1215)" NAME
  NAME=${NAME:-"polatengin"}
fi

if [ -z "$EMAIL" ]
then
  read -p "Please enter your git user.email, (for example, decoder[at]live[dot]de)" EMAIL
  EMAIL=${EMAIL:-"decoder@live.com"}
fi

if [ ! -z "$GPG_KEY" ]
then
  git config --global user.signingkey "$GPG_KEY"
  git config --global commit.gpgsign true
fi

process "→ Bootstrap steps start here:\n------------------"

process "→ upgrade and update apt packages"

  sudo apt-get update
  sudo apt-get -y upgrade

process "→ Installing snapd"

  sudo apt install snapd

process "→ install git"

  sudo apt install -y git

process "→ setup git config"

  git config --global user.name $NAME
  git config --global user.email $EMAIL

process "→ install essencial packages"

  sudo apt install -y vim-gtk htop unzip python3-setuptools figlet tmux pydf mc wget mtr ncdu cmatrix ranger jq lolcat tmux

process "→ install pip"

  sudo apt install -y python3-pip

process "→ install go"

  sudo apt install -y golang

process "→ install kubectl"

  cd /usr/local/bin
  sudo curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
  sudo chmod +x ./kubectl

process "→ install helm"

  curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

process "→ install terraform"
(
  cd /tmp
  wget https://releases.hashicorp.com/terraform/0.13.4/terraform_0.13.4_linux_amd64.zip
  unzip terraform_0.13.4_linux_amd64.zip
  sudo mv terraform /usr/local/bin/
)

process "→ install node and nmp"

  sudo apt install -y nodejs

process "→ install zsh and oh-my-zsh"

  sudo apt install -y zsh

  sudo rm -rf ~/.oh-my-zsh

  sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

process "→ Installing zsh-autosuggestions plugin"

  git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

# process "→ Installing stern"
# (
#     wget https://github.com/wercker/stern/releases/download/1.11.0/stern_linux_amd64 && \
#     sudo chmod +x stern_linux_amd64 && \
#     sudo mv stern_linux_amd64 /usr/local/bin/stern
# )

# process "→ Installing kubectx and kubens - quickly switch kubernetes context and namespace"

# sudo rm -drf /opt/kubectx

# (
#   git clone https://github.com/ahmetb/kubectx /opt/kubectx && \
#   ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx && \
#   ln -s /opt/kubectx/kubens /usr/local/bin/kubens
# )

process "→ Installing Okteto for local development"
  curl https://get.okteto.com -sSfL | sh

process "→ Installing alacritty"
  sudo snap install alacritty --classic

process "→ Installing Arkade"
  curl -sLS https://get.arkade.dev | sudo sh

process "→ Installing Neovim"
  mkdir -p ${HOME}/.config/nvim/
  ln -sf ${HOME}/dotfiles/init.vim ${HOME}/.config/nvim/init.vim
  sudo snap install --edge nvim --classic
  git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
  vim +PluginInstall +qall

process "→ Setting zsh as default shell"
sudo chsh -s $(which zsh) $(whoami)
  zsh
  sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="3den"/g' ~/.zshrc

process "→ Installation complete"
