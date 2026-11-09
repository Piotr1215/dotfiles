# Agent tab tmux switch

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
