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
wget https://raw.githubusercontent.com/Piotr1215/dotfiles/27c5e069d2dc239728e20dececce7e81db958949/create-test-user.sh
```

```bash
./create-test-user.sh -u "decoder" -p "test"
su decoder
cd
```

### Note on symlinking

Use `stow` to symling whole directories and exclude others, example

```bash
stow --ignore=".stfolder" --target=/home/decoder/.config/tmuxinator tmuxinator
```

### Clone the repo and install

```bash
git clone https://github.com/Piotr1215/dotfiles.git
cd dotfiles
./install.sh
```

Runing `./install` will

- backup existing dotfiles
- configure git with given user and email (default values point to my user)
- install bunch of programs and symling the right
- most notably, install neovim and configure its plugins
- arkade is also worth mentioning, it proxies installation of a lot of devops,
  cloud-native tools
- kubectl installed with krew plugin manager

### TODOS

- [ ] switch to arkade for installing devops CLIs
- [ ] TODO(decoder 2022-03-31): add tmuxinator sessions to the repo

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

[de5e2407](https://github.com/Piotr1215/dotfiles/de5e2407f58ebbef30534e0d7e3f939f99c8edcd) - Moving to awk based implmenetaion for the git log script
[0ff90d5b](https://github.com/Piotr1215/dotfiles/0ff90d5be42b2744668b527ae025bdd940850582) - Changelog
[eb1ad490](https://github.com/Piotr1215/dotfiles/eb1ad490fa58ac66633282482225c53232052206) - Mapping to insert quick changelog
[9ac32d87](https://github.com/Piotr1215/dotfiles/9ac32d87f7f0cfd301b5927ae6ab7f31d28949be) - Simple script to generate change log with last 10 commits
[f2af1f0c](https://github.com/Piotr1215/dotfiles/f2af1f0cc0f13892f67405316491be7795279d10) - Combine demos with slides
[7d53aa07](https://github.com/Piotr1215/dotfiles/7d53aa074202f1b0024dfea66a68fc40e143a061) - Nvim dap was multiple times in the scirpt, this messes up with packer
[f7b8dcc7](https://github.com/Piotr1215/dotfiles/f7b8dcc761df7ad9e17d6f3772e9eb2db01f3874) - Do not auto-wrap text, this messes up with the code fences
[27a106cc](https://github.com/Piotr1215/dotfiles/27a106cc3f678e0088f419a77acc9fc42387896d) - The dedicated mapping is not needed as arguments can be passed to ripgrep
[b7d455a5](https://github.com/Piotr1215/dotfiles/b7d455a5e240ff06740d97c467e6cc116370ffe3) - Livesearch option with ability to search directly in dev folder
[96250d35](https://github.com/Piotr1215/dotfiles/96250d35c26a0ddee754c202c8c66d8735191112) - yaml fodmethod indent for easier file transposing
