#!/usr/bin/env bash
# Custom preview hook for zsh-jumper
# TOKEN is already set and exported

# Linear issues
if [[ "$TOKEN" =~ (DEVOPS|DOC|ENG|IT)-[0-9]+ ]]; then
    ~/.config/zsh-jumper/scripts/linear-preview.sh
    exit 0
fi

# Return non-zero to fall through to default preview
exit 1
