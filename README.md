# Dotfiles Repo

Simple dotfiles with an installation script

> I guess not so simple any more

## Installation

Installation steps on a fresh Ubuntu/PoP_Os! distro.


### Clone the repo and install

```bash
git clone https://github.com/Piotr1215/dotfiles.git
cd dotfiles
chmod +x install.sh
./install.sh
```

Or run remotely:

- `bash -c "$(curl -fsSL https://raw.githubusercontent.com/Piotr1215/dotfiles/master/install.sh)"`

- `curl https://raw.githubusercontent.com/Piotr1215/dotfiles/master/install.sh | bash -s -- ${GIT_USERNAME} ${GIT_EMAIL} ${GPG_KEY}`

### Runing `./install` will

- backup existing dotfiles
- configure git with given user and email (default values point to my user)
- install bunch of programs and symlink them using stow
- most notably, install neovim and configure its plugins

> [!NOTE]
> Note On Symlinks:

The install script is using `stow` to symlink whole directories and exclude others.
You can symlink additional directories like so:

```bash
stow --target=/home/decoder/.config/tmuxinator tmuxinator
```

Adding new directory or file to the dotfiles repo can be done with the [__dotfiles_adder.sh](./scripts/__dotfiles_adder.sh) script

## Auto-config commit

Once the dotfiles are symlinked, it is easy to forget to commit them do the repo
(there is no indicator on the symlinked file).

> [!IMPORTANT]
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


## Testing

Creating user is only required for testing, in real installation you should already have a user (the script assumes you are running as a user).

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
The setup was tested on:

Last test date: 2024-12-29

- Ubuntu 20.04 vm

---

## License

<img src="https://kopimi.com/badges/modern-kopimi-logo.png" alt="kopimi_logo" style="width: 25%;">

All files and scripts in this repo are released [CC0](https://creativecommons.org/publicdomain/zero/1.0/) / [kopimi](https://kopimi.com)! in the spirit of _freedom of information_, i encourage you to fork, modify, change, share, or do whatever you like with this project!
