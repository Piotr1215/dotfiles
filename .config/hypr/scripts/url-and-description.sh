#!/usr/bin/env bash
set -eo pipefail

# Port of autokey "UrlAndDescription.py" for Wayland
# Browser: get selection + URL, choose action (Link/Task)

title=$(hyprctl activewindow -j | jq -r '.title')
[[ "$title" != *irefox* && "$title" != *ibreWolf* && "$title" != *hrome* ]] && exit 0

description=$(wl-paste -p 2>/dev/null || true)
wl-copy ""
wtype -M ctrl -k l -m ctrl
sleep 0.1
wtype -M ctrl -k c -m ctrl
sleep 0.2
url=$(wl-paste 2>/dev/null || true)
wtype -k Escape

[[ -z "$url" ]] && { notify-send "URL" "No URL captured"; exit 0; }

action=$(printf "Link\nTask\nMarkdown" | wofi --dmenu --prompt "Action for: ${description:0:30}" 2>/dev/null) || exit 0

case "$action" in
	Link)
		desc=$(zenity --entry --title="Link Description" --text="Description:" --entry-text="$description" --width=400 2>/dev/null) || exit 0
		PET_SNIPPET_FILE="$HOME/dev/pet-snippets/pet-links.toml" pet new -t <<-EOF
			xdg-open "$url"
			Link to $desc
			web link
		EOF
		notify-send "Pet" "Link saved: $desc"
		;;
	Task)
		desc=$(zenity --entry --title="Task Description" --text="Description:" --entry-text="$description" --width=400 2>/dev/null) || exit 0
		~/dev/dotfiles/scripts/__create_task.sh "$desc" "+web"
		notify-send "Task" "Created: $desc"
		;;
	Markdown)
		combined="[${description:-$title}](${url})"
		echo -n "$combined" | wl-copy
		notify-send "Markdown" "$combined"
		;;
esac
