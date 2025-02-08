#!/usr/bin/env bash
# Get the list of mailboxes
mailboxes=$(grep -i '^mailboxes' /home/decoder/.config/mutt/accounts/piotrzan@gmail.com.muttrc | sed 's/^mailboxes //')
# Use awk to process the mailboxes string and pipe to fzf for selection
selected=$(echo "$mailboxes" | awk -F'"' '{
    for (i=2; i<=NF; i+=2) {
        if ($i != "") {
            print $i
        }
    }
}' | fzf --height 40% --reverse)
# Output the move command for the selected mailbox
if [ -n "$selected" ]; then
	printf "push ':set confirmappend=no delete=yes<enter><tag-prefix><save-message>%s<enter><sync-mailbox>:set confirmappend=yes delete=ask-yes<enter>'" "$selected"
else
	echo "noop"
fi
