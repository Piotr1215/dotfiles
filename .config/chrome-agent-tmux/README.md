# Agent tab tmux switch

Claude in Chrome titles every agent group "Claude", so titles cannot identify an agent. Chrome now sends the activated `tabId`, its `groupId`, the ids of all tabs in that group and the group title. The host reads `${XDG_STATE_HOME:-~/.local/state}/agent-tabs/tabs.jsonl` (append-only, newest line per `tab_id` wins, written by a Claude hook), tries the tab id, then the newest group sibling, and switches the single attached client to that tmux pane (session, window and pane) if it still exists. The title match below stays as the last fallback. Replies carry `rule`: `tab_id`, `group_sibling` or `title`. Reload the unpacked extension in chrome://extensions after changing `background.js`.

Chrome sends activated tab group titles to the native host. The host switches
only if a pane in the exact matching session has the same `@agent_name`, and
only if exactly one tmux client is attached. Other tabs and ambiguous clients
leave tmux alone. The host never changes browser focus.

The native host manifest is installed at
`~/.config/google-chrome/NativeMessagingHosts/org.piotr.agent_tab_tmux.json`.
Run `python3 .config/chrome-agent-tmux/install-host.py` from this checkout to
install it again or update its absolute path after moving the checkout. Load this directory as an unpacked Chrome extension with
Developer mode enabled. The manifest key fixes its extension ID so Chrome can
match the native host's allowed origin.
