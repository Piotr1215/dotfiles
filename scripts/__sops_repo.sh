#!/usr/bin/env bash

set -e # Exit immediately if a command exits with a non-zero status.

# Function to install necessary tools
install_tools() {
	echo "Installing pre-commit and SOPS..."

	# Install pre-commit
	if ! command -v pre-commit &>/dev/null; then
		echo "Installing pre-commit..."
		pip install pre-commit
	else
		echo "pre-commit is already installed."
	fi

	# Install SOPS
	if ! command -v sops &>/dev/null; then
		echo "Installing SOPS..."
		if [[ "$OSTYPE" == "darwin"* ]]; then
			# MacOS
			brew install sops
		elif [[ "$OSTYPE" == "linux"* ]]; then
			# Linux
			sudo apt-get install -y sops
		else
			echo "Please install SOPS manually from: https://github.com/mozilla/sops/releases"
		fi
	else
		echo "SOPS is already installed."
	fi
}

# Function to generate a GPG key
generate_gpg_key() {
	echo "Generating GPG key..."
	if ! gpg --list-secret-keys --keyid-format=long | grep -q "sec"; then
		gpg --full-generate-key
	else
		echo "GPG key already exists."
	fi

	GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep "^sec" | awk '{print $2}' | cut -d'/' -f2)
	echo "GPG Key ID: $GPG_KEY_ID"
}

# Function to create pre-commit configuration
create_pre_commit_config() {
	echo "Creating .pre-commit-config.yaml..."
	cat <<EOL >.pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: sops-encrypt-notes
        name: SOPS encrypt notes
        entry: sops --encrypt --in-place notes/*.md
        language: system
        files: ^notes/.*\\.md\$
      - id: sops-decrypt-notes
        name: SOPS decrypt notes
        entry: sops --decrypt --in-place notes/*.md
        language: system
        files: ^notes/.*\\.md\$
EOL
}

# Function to create SOPS configuration
create_sops_config() {
	echo "Creating .sops.yaml..."
	cat <<EOL >.sops.yaml
creation_rules:
  - path_regex: notes/.*\\.md\$
    pgp: '$GPG_KEY_ID'
EOL
}

# Function to setup gitignore
setup_gitignore() {
	echo "Updating .gitignore..."
	if ! grep -q "notes/\\*.md" .gitignore; then
		echo "notes/*.md" >>.gitignore
	else
		echo ".gitignore already configured."
	fi

	git add .gitignore
	git commit -m "Ignore unencrypted notes"
	git push origin main
}

# Function to initialize pre-commit hooks
initialize_pre_commit_hooks() {
	echo "Installing pre-commit hooks..."
	pre-commit install
}

# Main function to orchestrate the setup
main() {
	install_tools
	generate_gpg_key
	create_pre_commit_config
	create_sops_config
	setup_gitignore
	initialize_pre_commit_hooks

	echo "Setup completed. Remember to manually encrypt your existing markdown files using:"
	echo "  sops --encrypt notes/your-file.md > notes/your-file.enc.md"
}

# Run the main function
main
