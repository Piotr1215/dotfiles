#!/usr/bin/env bash

set -e

# collect name and email and save it as git config, globally
NAME=$1
EMAIL=$2
GPG_KEY=$3

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

git config --global user.name $NAME
git config --global user.email $EMAIL

if [ ! -z "$GPG_KEY" ]
then
  git config --global user.signingkey "$GPG_KEY"
  git config --global commit.gpgsign true
fi

echo 'Bootstrap steps start here:\n------------------'

echo '[STEP 1] upgrade and update apt packages'

sudo apt-get update
sudo apt-get -y upgrade

echo '[STEP 2] install essencial packages'

sudo apt install -y vim-gtk htop unzip python3-setuptools figlet tmux pydf mc wget mtr ncdu cmatrix ranger jq gdu

echo '[STEP 3] install pip'

sudo apt install -y python3-pip

echo '[STEP 4] install go'

sudo apt install -y golang

echo '[STEP 5] install kubectl'

cd /usr/local/bin
sudo curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
sudo chmod +x ./kubectl

echo '[STEP 6] install helm'

curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

echo '[STEP 7] install terraform'

cd /tmp
wget https://releases.hashicorp.com/terraform/0.13.4/terraform_0.13.4_linux_amd64.zip
unzip terraform_0.13.4_linux_amd64.zip
sudo mv terraform /usr/local/bin/

echo '[STEP 8] install node and nmp'

sudo apt install -y nodejs npm

echo '[STEP 9] install zsh'

sudo rm -rf ~/.oh-my-zsh

sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

echo '[STEP 10] Installing zsh-autosuggestions plugin'

git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

echo '[STEP 11] Installing stern'
(
    wget https://github.com/wercker/stern/releases/download/1.11.0/stern_linux_amd64 && \
    chmod +x stern_linux_amd64 && \
    sudo mv stern_linux_amd64 /usr/local/bin/stern
)

# echo '[STEP 12] Installing kubectx and kubens - quickly switch kubernetes context and namespace'

# sudo rm -drf /opt/kubectx

# (
#   git clone https://github.com/ahmetb/kubectx /opt/kubectx && \
#   ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx && \
#   ln -s /opt/kubectx/kubens /usr/local/bin/kubens
# )

echo '[STEP 13] Installing Okteto for local development'
curl https://get.okteto.com -sSfL | sh

echo '[STEP 14] Install tmux with cool customizations'
git clone https://github.com/samoshkin/tmux-config.git
./tmux-config/install.sh

echo '[STEP 15] Setting zsh as default shell'
chsh -s $(which zsh)

echo '[STEP 16] Installation complete'
