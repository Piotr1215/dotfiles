# Dotfiles Repo

Simple dotfiles with an installation script

## Installation

Installation steps on a fresh Ubuntu/PoP_Os! distro.

### Create User

Create a user, in my case user name is `decoder`, and switch to the user
directory.

For testing purposes, password is "test", use real password for real
installation ofc :)

```bash
wget https://raw.githubusercontent.com/Piotr1215/dotfiles/master/create-test-user.sh
```

```bash
sudo chmod +x chreate-test-user.sh
./create-test-user.sh -u "decoder" -p "testingme"
sudo passwd decoder
su decoder
cd
```

### Clone the repo and install

```bash
git clone https://github.com/Piotr1215/dotfiles.git
cd dotfiles
chmod +x install.sh
./install.sh
```

### Symlink all the things

Once the installation is completed run the following command from the `dotfiles`
directory.

```bash
stow . --restow --adopt
```

### Note on symlinks

The install script is using `stow` to symlink whole directories and exclude others.
You can symlink additional directories like so:

```bash
stow --ignore=".stfolder" --target=/home/decoder/.config/tmuxinator tmuxinator
```

Runing `./install` will

- backup existing dotfiles
- configure git with given user and email (default values point to my user)
- install bunch of programs and symlink them using stow
- most notably, install neovim and configure its plugins
  cloud-native tools
- kubectl installed with krew plugin manager

### TODOS

- [x] switch to arkade for installing devops CLIs
- [x] TODO(decoder 2022-03-31): add tmuxinator sessions to the repo

## Auto-config commit

Once the dotfiles are symlinked, it is easy to forget to commit them do the repo
(there is no indicator on the symlinked file).

FIRST COPY FILE TO THIS REPO AND THAN SYMLINK IT IN THE DESTINATION FOLDER NOT
OTHER WAY AROUND!!!

To symlink a file: (source -> destination)

```bash
# This will create symlink on the filesystem FROM the file in the repo TO the file in the filesystem
# So you end up with symlinks in the file system and actual files in the repo!
ln -sf /path/to/file_in_this_repo /path/to/symlink_name_in_whatever_folder_locally
```

> IMPORTANT: Once a file is added to the repo folder, it will be auto-committed.

Use this systemd service to automate this process

### Create a service

```bash
touch /lib/systemd/system/checkfile.service
vim /lib/systemd/system/checkfile.service

[Unit]
Description = Run inotify-hookable in background to always sync my dotfiles with github repo

[Service]
User=decoder
Group=decoder
ExecStart=/bin/bash /home/decoder/scripts/zshsync.sh
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Install inotify-hookable

sudo apt install inotify-hookable -y

### Write script

This script watches a folder with dotfiles and every time a change to a file is
made or a new file is created, commits everything and pushes to git. This also
works of course if the changes are made on the symlinked files.

```bash
cd /home/decoder/dev/dotfiles
while true; do
    inotify-hookable \
     --watch-files ./ \
     --on-modify-command "git add . && git commit -m 'auto commit' && git push origin master"
done
```

### Enable and start the service

- `sudo systemctl daemon-reload`
- `sudo systemctl enable checkfile`
- `sudo systemctl start checkfile`

### Monitor the service

`journalctl -fu checkfile.service`

## How to run

Either

`bash -c "$(curl -fsSL https://raw.githubusercontent.com/Piotr1215/dotfiles/master/install.sh)"`

or

`curl https://raw.githubusercontent.com/Piotr1215/dotfiles/master/install.sh | bash -s -- ${GIT_USERNAME} ${GIT_EMAIL} ${GPG_KEY}`

## Testing

The setup was tested on:

Last test date: 18.03.2022

- Ubuntu 20.04
- Pop!\_OS 21.04
- Katacoda testbed:
  <https://www.katacoda.com/scenario-examples/courses/environment-usages/ubuntu-2004>

## Changelog

- [45369094](https://github.com/Piotr1215/dotfiles/4536909435c495dd9d0d11418beee9a9d81ab30e) - Adding obsidian mappings
- [7b07b5e2](https://github.com/Piotr1215/dotfiles/7b07b5e2f16dbe504e247d142d54848e08d8c47c) - Startup pane was not loading correctly
- [6646ba0b](https://github.com/Piotr1215/dotfiles/6646ba0be82597caa99eacc058c2838a56ba12dc) - Adding comment to easier find quickfix plugin
- [e870c1b6](https://github.com/Piotr1215/dotfiles/e870c1b695042e1c1dade8ebc66dc439c9dec5cd) - Startify session for dotfiles
- [fa5c9cec](https://github.com/Piotr1215/dotfiles/fa5c9cecac043d534e32af966332b96d991b6fd7) - Sort done projects desdending
- [bb6bd211](https://github.com/Piotr1215/dotfiles/bb6bd21178b49797e4624635660983ea34b3c68e) - Ability to override provider GCP version from environmental variable
- [7ae3cca9](https://github.com/Piotr1215/dotfiles/7ae3cca91feea3eb770d9878ef5a01a698f789ce) - Pipe to less with case insensitive search and color output from cat
- [b98b5c3f](https://github.com/Piotr1215/dotfiles/b98b5c3fb658e0afc87e961e43f79128f3fe1774) - aliases cleanup
- [8fbe9fe7](https://github.com/Piotr1215/dotfiles/8fbe9fe76e8cb7679900349593949f6f7f4c7339) - full tasks description in completed
- [54008228](https://github.com/Piotr1215/dotfiles/54008228e2a980c77b78fa074b6bd23af21ce915) - upgrading uxp setup for providers
