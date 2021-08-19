# Dotfiles Repo

Simplified version without dotbot:

- run install
- symlink all the .files
- TODO: automate symlinking

## How to run

either

`bash -c "$(curl -fsSL https://raw.githubusercontent.com/Piotr1215/dotfiles/master/install.sh)"`

or `curl https://raw.githubusercontent.com/Piotr1215/dotfiles/master/install.sh | bash -s -- ${GIT_USERNAME} ${GIT_EMAIL} ${GPG_KEY}`