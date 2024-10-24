#!/usr/bin/env bash

set -eo pipefail
IFS=$'\n\t'

user=$(whoami)

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
	for i in $(ls -d */ | sed 's/.$//'); do stow -t $HOME "$i"; done;}

# For all files `$name` in the present folder except `*.sh`, `README.md`, `settings.json`,
# and `config`, backup the target file located at `~/.$name` and symlink `$name` to `~/.$name`
for name in *; do
	if [ ! -d "$name" ]; then
		target="$HOME/.$name"
		if [[ ! "$name" =~ '\.sh$' ]] && [ "$name" != 'README.md' ] && [[ "$name" != 'settings.json' ]] && [[ "$name" != 'config' ]]; then
			backup "$target"
		fi
	fi
done

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

process "→ Copy .stow-ignore file to home directory"

cp "${HOME}"/dotfiles/.stow-local-ignore ~/

process "→ upgrade and update apt packages"

sudo apt-get update
sudo apt-get -y upgrade

process "→ Installing snapd"

sudo apt install snapd

process "→ install git"

sudo apt install -y git

process "→ setup git config"

git config --global user.name "$NAME"
git config --global user.email "$EMAIL"

process "→ install essencial packages"

sudo apt install -y vim-gtk htop unzip python3-setuptools figlet tmux pydf mc wget mtr ncdu cmatrix  jq lolcat tmux bat locate libgraph-easy-perl stow cowsay fortune
sudo apt install -y encfs fuse xclip xsel alsa-utils fd-find expect bat

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
cargo install onefetch

process "→ Install PipeWire for audio management"

sudo apt install -y pipewire pipewire-utils

process "→ install kubectl"
cd /usr/local/bin
sudo curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
sudo chmod +x ./kubectl

process "→ install helm"
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

process "→ install kube-ps1"
git clone https://github.com/jonmosco/kube-ps1.git "${HOME}"/kube-ps1/

process "→ install node and nmp"
sudo apt install -y nodejs

process "→ install zsh and oh-my-zsh"
sudo apt install -y zsh
sudo rm -rf ~/.oh-my-zsh
sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

process "→ Installing zsh-autosuggestions plugin"
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

process "→ Installing krew kubectl plugin"
set -x
cd "$(mktemp -d)" &&
	curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/download/v0.3.4/krew.{tar.gz,yaml}" &&
	tar zxvf krew.tar.gz &&
	KREW=./krew-"$(uname | tr '[:upper:]' '[:lower:]')_amd64" &&
	"$KREW" install --manifest=krew.yaml --archive=krew.tar.gz &&
	"$KREW" update

process "→ Installing alacritty"
sudo snap install alacritty --classic
mkdir -p ${HOME}/.config/alacritty/

process "→ Installing Arkade"
curl -sLS https://get.arkade.dev | sudo sh

process "→ Installing gh, k9s, kind, krew"
arkade get gh \
           k9s \
					 kind \
					 kubectx \
					 kubens \
					 yq

echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >>~/.zshrc

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

symlink

nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'

process "→ Setting zsh as default shell"
cd "$HOME"
sudo chsh -s $(which zsh) "$user"
zsh
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="3den"/g' ~/.zshrc
source ~/.zshrc
exec zsh

process → Installation complete"
