# Dotfiles Repo

Simplified version without dotbot:

- run install
- symlink all the .files
- TODO: automate symlinking

## Auto-config commit

Once the dotfiles are symlinked, it is easy to forget to commit them do the repo (there is no indicator on the symlinked file).

FIRST COPY FILE TO THIS REPO AND THAN SYMLINK IT IN THE DESTINATION FOLDER NOT OTHER WAY AROUND!!!

To symlink a file: (source ->  destination)

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

This script watches a folder with dotfiles and every time a change to a file is made or a new file is created, commits everything and pushes to git. This also works of course if the changes are made on the symlinked files.

``` bash
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
- Ubuntu 20.04
- Pop!_OS 21.04

