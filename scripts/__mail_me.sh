#!/usr/bin/env bash
# Mail stdin to Piotr through msmtp, the `M` global alias as a script so a
# reminder's :runs: command and the reminder itself can use it from bash.
# Usage: <command> 2>&1 | __mail_me.sh "<subject>"
set -eo pipefail

subject="${1:-pop-os-automated-email}"
recipient="${MAIL_ME_RECIPIENT:-piotrzan@gmail.com}"
{
	printf 'Subject: %s\nFrom: %s\nTo: %s\n\n' "$subject" "$recipient" "$recipient"
	sed -r 's/\x1b\[[0-9;]*m//g'
} | msmtp "$recipient"
