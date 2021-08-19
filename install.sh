#!/usr/bin/env bash

set -e

# collect name and email and save it as git config, globally
NAME=$1
EMAIL=$2
GPG_KEY=$3

if [ -z "$NAME" ]
then
  read -p "Please enter your git user.name, (for example, polatengin)" NAME
  NAME=${NAME:-"polatengin"}
fi

if [ -z "$EMAIL" ]
then
  read -p "Please enter your git user.email, (for example, polatengin[at]outlook[dot]com)" EMAIL
  EMAIL=${EMAIL:-"polatengin@outlook.com"}
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

sudo apt install -y vim-gtk htop unzip python3-setuptools figlet tmux screenfetch pydf mc wget nnn mtr bpytop ncdu cmatrix ranger jq

echo '[STEP 3] install yq'

sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys CC86BB64
sudo add-apt-repository ppa:rmescandon/yq
sudo apt update
sudo apt install yq -y

echo '[STEP 4] install pip'

sudo apt install -y python3-pip

echo '[STEP 5] install go'

sudo apt install -y golang

echo '[STEP 6] install kubectl'

cd /usr/local/bin
sudo curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
sudo chmod +x ./kubectl

echo '[STEP 7] install helm'

curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

echo '[STEP 8] install terraform'

cd /tmp
wget https://releases.hashicorp.com/terraform/0.13.4/terraform_0.13.4_linux_amd64.zip
unzip terraform_0.13.4_linux_amd64.zip
sudo mv terraform /usr/local/bin/

echo '[STEP 9] install node and nmp'

sudo apt install -y nodejs npm

echo '[STEP 10] install zsh'

sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended