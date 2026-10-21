#!/usr/bin/env bash
# PROJECT: mail-attention
# Prints one mail account's IMAP password by running the PassCmd mbsync uses
# for it, so goimapnotify (passwordCMD in .config/goimapnotify/goimapnotify.yaml)
# shares mbsync's credential source and nothing about it lives in git.
#
# The account is the User of an IMAPStore block in the mbsync config. The
# command is never printed, only its output.
#
# Usage: __mail_passcmd.sh <account>
# Env: MAIL_PASSCMD_MBSYNCRC (mbsync config, default ~/.mbsyncrc)
set -eo pipefail

RC="${MAIL_PASSCMD_MBSYNCRC:-$HOME/.mbsyncrc}"

# passcmd_of <account>: the PassCmd value of the IMAPStore whose User is the
# account, with mbsync's quoting and its interactive "+" removed.
passcmd_of() {
    awk -v want="$1" '
        function flush() { if (user == want && cmd != "") { print cmd; found = 1; exit } }
        /^[[:space:]]*(IMAPStore|IMAPAccount|MaildirStore|Channel|Group)[[:space:]]/ { flush(); user = ""; cmd = "" }
        $1 == "User" { user = $2 }
        $1 == "PassCmd" { sub(/^[[:space:]]*PassCmd[[:space:]]+/, ""); cmd = $0 }
        END { if (!found) flush() }
    ' "$RC" | sed -E 's/^"(.*)"[[:space:]]*$/\1/; s/^\+//; s/\\"/"/g; s/\\\\/\\/g'
}

main() {
    local account="$1" cmd
    if [[ -z "$account" ]]; then
        echo "usage: ${0##*/} <account>" >&2
        exit 1
    fi
    [[ -r "$RC" ]] || {
        echo "ERROR: cannot read $RC" >&2
        exit 1
    }
    cmd="$(passcmd_of "$account")"
    [[ -n "$cmd" ]] || {
        echo "ERROR: no IMAPStore with User $account and a PassCmd in $RC" >&2
        exit 1
    }
    exec sh -c "$cmd"
}

main "$@"
