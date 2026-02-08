# Dotfiles Repo

Simple dotfiles with an installation script.

[![Video Thumbnail](https://img.youtube.com/vi/_ttF5InNuMI/0.jpg)](https://www.youtube.com/watch?v=_ttF5InNuMI)

## Hyprland

This repo includes a full [Hyprland](https://hypr.land/) Wayland compositor setup as an alternative desktop environment (selectable at GDM login).

Config lives in `.config/hypr/` with custom scripts for window layouts, Alt+Tab cycling, emoji picker, and URL launcher. Waybar theme is Golden Noir, adapted from [JaKooLit/Hyprland-Dots](https://github.com/JaKooLit/Hyprland-Dots).

## What are Dotfiles?

Dotfiles are configuration files for Unix-like systems, named for their leading dot (e.g., `.bashrc`, `.vimrc`). This repo stores my personal configs for easy setup across machines.

## Installation

Installation steps for Debian-based systems:

1. Clone the repository:
```bash
git clone https://github.com/Piotr1215/dotfiles.git
cd dotfiles/install
```

2. Run the installation:
```bash
chmod +x install.sh
./install.sh
```

The installation script will:
1. Install [ansible](https://www.ansible.com/) if not present
2. Run the ansible playbook which will:
   - Configure git with your credentials
   - Install and configure all necessary tools and programs
   - Set up development environment (neovim, tmux, etc.)
   - Configure shell environment (zsh, oh-my-zsh)
   - Install DevOps tools (kubectl, helm, etc.)

### Advanced Usage

You can run specific parts of the installation using Ansible tags:
```bash
# List all available tasks
ansible-playbook install.yml --list-tasks

# Install specific components (e.g., just Alacritty)
ansible-playbook install.yml --tags "alacritty"
```

Or run remotely:

- `bash -c "$(curl -fsSL https://raw.githubusercontent.com/Piotr1215/dotfiles/master/install.sh)"`

- `curl https://raw.githubusercontent.com/Piotr1215/dotfiles/master/install.sh | bash -s -- ${GIT_USERNAME} ${GIT_EMAIL} ${GPG_KEY}`

### Runing `./install` will

- configure git with given user and email (default values point to my user)
- install a bunch of programs and symlink them using stow
- set up shell environment with zsh and oh-my-zsh configuration
- most notably, install neovim and configure its plugins

> [!NOTE]
> Symlinks:

Any existing dotfiles will be pulled into the dotfiles repo, please make sure that you are not overwriting anything you don't want to. Check git status before committing.

The installation script is using `stow` to symlink whole directories and exclude others.
You can symlink additional directories like so:

```bash
stow --target=/home/decoder/.config/tmuxinator tmuxinator
```

Adding new directory or file to the dotfiles repo can be done with the [__dotfiles_adder.sh](./scripts/__dotfiles_adder.sh) script

## Encrypted Files

This repository uses [git-crypt](https://github.com/AGWA/git-crypt) for encrypting sensitive files. The following files are encrypted:

- `.vsnip/global.json` — VSCode snippets file

### Setting up git-crypt for new devices

After cloning the repository, you'll need the encryption key to decrypt these files:

```bash
# Install git-crypt (Debian/Ubuntu)
sudo apt install git-crypt

# For other systems, see: https://github.com/AGWA/git-crypt#installing-git-crypt

# Copy the encryption key to your new machine
# (securely transfer the .keys/git-crypt-key file)

# Unlock the repository with the key
git-crypt unlock /path/to/git-crypt-key
```

Once unlocked, encrypted files will automatically be decrypted when checked out and encrypted when committed.

## Testing

Creating user is only required for testing, in real installation you should already have a user (the script assumes you are running as a user).

Create a user, in my case username is `decoder`, and switch to the user
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

All files and scripts in this repo are released [CC0](https://creativecommons.org/publicdomain/zero/1.0/) / [kopimi](https://kopimi.com)! In the spirit of _freedom of information_, I encourage you to fork, modify, change, share, or do whatever you like with this project!
