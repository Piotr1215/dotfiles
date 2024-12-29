#!/usr/bin/env bash

set -eo pipefail
IFS=$'\n\t'

user=$(whoami)

# Set variables
NAME=$1
EMAIL=$2
GPG_KEY=$3

LOG="${HOME}/dotfiles.log"

process() {
	echo "$(date) PROCESSING:  $@" >>$LOG
	printf "$(tput setaf 6) [STEP ${STEP:-0}] %s...$(tput sgr0)\n" "$@"
	STEP=$((STEP + 1))
}

if [ -z "$NAME" ]; then
	read -r -p "Please enter your git user.name, (for example, piotr1215)" NAME
	NAME=${NAME:-"Piotr1215"}
fi

if [ -z "$EMAIL" ]; then
	read -r -p "Please enter your git user.email, (for example, decoder[at]live[dot]de)" EMAIL
	EMAIL=${EMAIL:-"decoder@live.com"}
fi

if [ -z "$GPG_KEY" ]; then
	git config --global user.signingkey "$GPG_KEY"
	git config --global commit.gpgsign true
	git config --global core.excludesFile "$HOME"/.gitignore
fi

process "→ Bootstrap steps start here:\n------------------"


process "→ upgrade and update apt packages"

sudo apt-get update
sudo apt-get -y upgrade

process "→ Stow dotfiles first"

sudo apt install -y stow
stow -R -v -t ~ . --adopt

process "→ Installing snapd"

sudo apt install snapd

process "→ install git"

sudo apt install -y git

process "→ setup git config"

git config --global user.name "$NAME"
git config --global user.email "$EMAIL"

process "→ install essencial packages"

sudo apt install -y vim-gtk htop unzip python3-setuptools figlet tmux pydf mc wget mtr ncdu cmatrix  jq lolcat tmux bat locate libgraph-easy-perl cowsay fortune
sudo apt install -y xclip xsel alsa-utils fd-find expect bat

process "→ install tmuxinator"
sudo gem install tmuxinator

process "→ install pip"
sudo apt install -y python3-pip

process "→ install exa"
EXA_VERSION=$(curl -s "https://api.github.com/repos/ogham/exa/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
curl -Lo exa.zip "https://github.com/ogham/exa/releases/latest/download/exa-linux-x86_64-v${EXA_VERSION}.zip"
sudo unzip -q exa.zip bin/exa -d /usr/local
sudo rm exa.zip

process "→ install go"
sudo apt install -y golang

process "→ Install development tools and package managers"

sudo apt install -y cargo
cargo install just
cargo install zoxide

process "→ Install PipeWire for audio management"

sudo apt install -y pipewire pipewire-utils

process "→ Installing Arkade"
curl -sLS https://get.arkade.dev | sudo sh

process "→ install devops tools"
arkade get kubectl helm gh k9s kind kubectx kubens yq eksctl gptscript jq kube-linter op popeye terraform trivy vcluster fzf krew
arkade system install go node

process "→ install kube-ps1"
git clone https://github.com/jonmosco/kube-ps1.git "${HOME}"/kube-ps1/

process "→ install zsh and oh-my-zsh"
sudo apt install -y zsh
sudo rm -rf ~/.oh-my-zsh
sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

process "→ Installing zsh-autosuggestions plugin"
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

process "→ Installing alacritty"
sudo snap install alacritty --classic
mkdir -p ${HOME}/.config/alacritty/

process "→ Installing Azure CLI"
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

process "→ Installing AWS CLI"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

process "→ Installing GCP CLI"
curl "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-377.0.0-linux-x86_64.tar.gz" -o "google-cloud-sdk-377.0.0-linux-x86.tar.gz"
tar zxvf google-cloud-sdk-377.0.0-linux-x86.tar.gz
./google-cloud-sdk/install.sh --usage-reporting=false --quiet

process "→ Installing Neovim"
sudo curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
sudo chmod +x nvim.appimage
sudo mv nvim.appimage /usr/local/bin/nvim
sudo chown "$user" /usr/local/bin/nvim

process "→ Setting zsh as default shell"
cd "$HOME"
sudo chsh -s $(which zsh) "$user"
zsh
source ~/.zshrc
exec zsh

process → Installation complete"
