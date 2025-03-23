#!/usr/bin/env bash

set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __edit_systemd_service.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

selected_service=$(systemctl --user list-units --type=service --state=running | 
  grep -v "LOAD\|●" | 
  awk '{print $1}' | 
  grep '\.service' | 
  fzf --height 40% \
      --layout=reverse \
      --border \
      --preview "systemctl --user status {} | bat --color=always --language=ini" \
      --preview-window=right:60% \
      --bind "ctrl-r:reload(systemctl --user list-units --type=service --state=running | grep -v 'LOAD\|●' | awk '{print \$1}' | grep '\.service')" \
      --bind "ctrl-e:reload(systemctl --user list-units --type=service --state=failed | grep -v 'LOAD\|●' | awk '{print \$1}' | grep '\.service')" \
      --bind "ctrl-a:reload(systemctl --user list-unit-files --type=service | grep -v 'UNIT FILE' | awk '{print \$1}' | grep '\.service')" \
      --header "CTRL-R: Running | CTRL-E: Failed | CTRL-A: All Services" \
      --info=inline \
      --prompt "Select service to edit > ")

if [ -n "$selected_service" ]; then
    systemctl --user edit --full "$selected_service"
    # Reload after editing
    systemctl --user daemon-reload
    echo "Service $selected_service edited. Daemon reloaded."
else
    echo "No service selected"
fi
