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

Last test date: Sun 26 Feb 18:23:57 CET 2023

- Ubuntu 20.04 vm

---

# Taskwarrior setup

Taskwarrior setup is highly customized and thus requires a decided
documentation section.

Taskwarrior uses custom `hooks` and `scripts` to add and extend the workflow.

## Developer Workflow for Task Management with TaskWarrior and Neovim

### Introduction

This workflow guides you through an integrated approach to managing tasks using TaskWarrior and Neovim. It aims to streamline task management directly within the coding environment.

### Workflow Steps

#### 1. Write Code and Add TODO Comments

While actively writing code, you might come up with a new task idea. To make a note of this, simply add a TODO comment in your code:

```bash
# TODO: use shift to get rid of the argument
```

#### 2. Convert TODO to TaskWarrior Task

Turn your `TODO:` comment into a TaskWarrior task by using a Neovim shortcut. In insert mode, press `Ctrl+t` to trigger this action. You can then add additional details like project and tags:

```bash
project: bash
tags: techniques learning
```

#### 3. Jump to Task Location in Code

The next day, open TaskWarrior's Task User Interface (TUI). Your new task will appear there. Simply press `1` to jump directly to the corresponding line in the code file.

#### 4. Add Context to Task

While working on the task, you may want to add more context, like a URL. Use `<leader>gt` in Neovim to open the task in the TUI. Press `A` to add the URL, then `Ctrl+C` to exit, and you'll be returned to the same line in your editor.

#### 5. Open TUI Session

The TUI session is fast and ephemeral, thanks to tmux integration. It's a seamless experience while working on your tasks.

#### 6. Remove Completed Task

Once the task is completed, select it in the TUI, then press `1` to jump to it in the code file. Use `<leader>dt` in Neovim to remove the task. The corresponding task will also be removed in the TUI.

#### 7. Remove Task Directly in TUI

Wondering what happens if you remove the task directly from the TUI first? As of the latest update, doing this will automatically remove the corresponding TODO comment in the code file. To create a new task for a TODO comment, simply use `Ctrl+t` in Neovim to add it to TaskWarrior.

## Duration Field and Logic in Taskwarrior Script

### Duration Field

- **What It Is**: The `duration` field in Taskwarrior stores the estimated amount of time it will take to complete a specific task. The value is stored as an ISO 8601 duration string, like `PT15M` for 15 minutes.

### Logic Surrounding Duration

- **Start Time**: When a task is started, Taskwarrior records the start time.
- **End Time**: When a task is stopped, Taskwarrior records the end time.
- **Time Exceeded**: If the actual time taken to complete a task exceeds the estimated duration, the script annotates the task with a message.

  - **Annotation Format**: The annotation specifies when the task was completed and by how much the estimated time was exceeded.
  - **Example Annotation**: `2023-09-25 18:31:38 -- Exceeded estimated time by 2 minutes.`

### Why is it

1. **Task Start**: On task start, capture the current time.

2. **Task Stop**: On task stop, capture the current time and compare it with the estimated duration. If the actual duration exceeds the estimated duration, an annotation is added to the task.

3. **Multiple Exceeds**: If the task's actual duration exceeds the estimated duration multiple times, each occurrence should be recorded as a separate annotation.
