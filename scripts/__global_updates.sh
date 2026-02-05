#!/usr/bin/env bash

set -uo pipefail
IFS=$'\n\t'

if ! command -v pueue &>/dev/null; then
    echo "pueue not installed" >&2
    exit 1
fi

pueue clean
pueue group add updates 2>/dev/null || true
pueue parallel 7 -g updates

add_update() {
    local name="$1"
    shift
    if command -v "$1" &>/dev/null; then
        pueue add -g updates -l "$name" -- "$@"
    fi
}

add_update "apt-update" sudo apt update
add_update "apt-upgrade" sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confold"
add_update "snap" sudo snap refresh
add_update "flatpak" flatpak update -y
add_update "pipx" pipx upgrade-all
add_update "npm" sudo npm update -g
add_update "tldr" tldr --update
add_update "go" go-global-update
add_update "cargo" cargo install-update -a
add_update "locate" sudo updatedb

echo "Tasks queued. Run: pueue status -g updates"
