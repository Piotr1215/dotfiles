#!/usr/bin/env bash
set -eo pipefail

accounts=$(ykman oath accounts list 2>/dev/null || true)
count=0
[ -n "$accounts" ] && count=$(echo "$accounts" | wc -l)

if [ "$count" -eq 0 ]; then
    echo "<tt><b>🔑:</b></tt><tt><span color='#666666'>0</span></tt> | font='monospace' size=12"
    echo "---"
    echo "No TOTP accounts on YubiKey"
else
    echo "<tt><b>🔑:</b></tt><tt><span color='#44ff44'>${count}</span></tt> | font='monospace' size=12"
    echo "---"
    echo "$accounts" | while read -r account; do
        [ -z "$account" ] && continue
        echo "${account} | bash='/home/decoder/.config/argos/.totp-copy.sh \"${account}\"' terminal=false"
    done
fi

echo "---"
echo "Refresh | refresh=true"
