#!/bin/bash

# Get manually installed packages
manually_installed=$(zcat /var/log/apt/history.log.*.gz | cat - /var/log/apt/history.log | grep -Po '^Commandline:(?=.* install ) \K.*' | sed '1,4d')

# Get all installed packages from nala
nala_installed=$(sudo nala list -i -N | grep -E '^\w' | awk '{print $1}')

echo "Manually installed by apt:"
echo "$manually_installed"

echo -e "\nManually installed by nala:"
echo "$nala_installed"
