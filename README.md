# Dotfiles Repo

Simplified version without dotbot:

- run install
- symlink all the .files
- TODO: automate symlinking

## Auto-config commit

## How to run

either

`bash -c "$(curl -fsSL https://raw.githubusercontent.com/Piotr1215/dotfiles/master/install.sh)"`

or `curl https://raw.githubusercontent.com/Piotr1215/dotfiles/master/install.sh | bash -s -- ${GIT_USERNAME} ${GIT_EMAIL} ${GPG_KEY}`

## Testing

The setup was tested on Ubuntu 20.04 VM, works.
