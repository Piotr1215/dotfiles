#!/usr/bin/env bash
set -eo pipefail

# Port of Random-6-char-string.py - type random 6-char string
wtype "$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c6)"
